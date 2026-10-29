import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = MenuBarPreferences()
    private let store = RulesStore()
    private lazy var engine = RuleEngine(preferences: preferences)
    private let monitor = FullscreenMonitor()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let defaultItem = NSMenuItem(title: "Hide Menu Bar", action: nil, keyEquivalent: "")
    private let customItem = NSMenuItem(title: "Hide Menu Bar for App", action: nil, keyEquivalent: "")
    private var defaultChoices: [NSMenuItem] = []
    private var customChoices: [NSMenuItem] = []
    private var menuTarget: AppContext?
    private var menuOpen = false
    private var preferencesObserver: [NSObjectProtocol] = []
    private var settingsCommandObserver: NSObjectProtocol?
    private var lastSnapshot: SettingsSnapshot?
    private var permissionRequestID: String?
    private var failure: String?
    private var settingsMessage: String?
    private var warning: String?
    private var reconciling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "love.oluwaseun.MenuBarToggle").count <= 1 else {
            NSApp.terminate(nil); return
        }
        // Recover a temporary override after an interrupted run, but preserve
        // any different setting chosen since then by another actor.
        if let recovery = store.recovery {
            do {
                if preferences.currentMode() == recovery.applied { try preferences.apply(recovery.baseline) }
                store.recovery = nil
            } catch { failure = error.localizedDescription }
        }
        if store.configuration.defaultMode == nil { store.configuration.defaultMode = preferences.currentMode() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Headroom")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityLabel("Headroom")
        defaultItem.keyEquivalentModifierMask = []
        defaultItem.submenu = makeChoices(custom: false)
        customItem.isAlternate = true
        customItem.keyEquivalentModifierMask = .option
        customItem.submenu = makeChoices(custom: true)
        menu.addItem(defaultItem)
        menu.addItem(customItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let about = NSMenuItem(title: "About Headroom", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Headroom", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        installAppMenu()
        for name in SystemPreferences.notifications {
            preferencesObserver.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.monitor.schedule() })
        }
        monitor.interestedBundles = store.configuration.enabled ? Set(store.configuration.rules.keys) : []
        monitor.didChange = { [weak self] context, trusted in self?.reconcile(context, trusted: trusted) }
        settingsCommandObserver = DistributedNotificationCenter.default().addObserver(forName: SettingsBridge.command, object: SettingsBridge.owner, queue: .main) { [weak self] note in
            guard let command = SettingsBridge.decode(note) else { return }
            self?.handleSettingsCommand(command)
        }
        monitor.start()
        refreshMenu()
        if CommandLine.arguments.contains("--show-settings") || !UserDefaults.standard.bool(forKey: "hasSeenAppRulesSettings.v1") {
            UserDefaults.standard.set(true, forKey: "hasSeenAppRulesSettings.v1")
            showSettings()
        }
    }

    private func installAppMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let item = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        item.target = self
        appMenu.addItem(item)
        let about = NSMenuItem(title: "About Headroom", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        let quit = NSMenuItem(title: "Quit Headroom", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        NSApp.mainMenu = main
    }
    private func makeChoices(custom: Bool) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for mode in MenuBarMode.allCases {
            let item = NSMenuItem(title: mode.title, action: custom ? #selector(selectCustom(_:)) : #selector(selectDefault(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
            item.target = self
            submenu.addItem(item)
            if custom { customChoices.append(item) } else { defaultChoices.append(item) }
        }
        return submenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        warning = nil
        menuTarget = nil
        refreshMenu()
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Only the explicit menu interaction inspects an unconfigured app.
        monitor.readCurrent(includeUnconfigured: true) { [weak self] context, trusted in
            guard let self, self.menuOpen, context.pid == pid else { return }
            if trusted, context.fullscreen == true,
               context.bundleID != Bundle.main.bundleIdentifier { self.menuTarget = context }
            self.refreshMenu()
        }
    }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    private func refreshMenu() {
        let config = store.configuration
        statusItem.isVisible = config.showMenuBarIcon
        let target = menuTarget
        let available = target != nil && monitor.trusted && config.defaultMode != nil
        defaultItem.subtitle = available ? "Default · Hold ⌥ to customize \(target!.name)"
            : monitor.trusted ? "Default · Fullscreen app settings in Settings…" : "Default · Set up app rules in Settings…"
        customItem.title = "Hide Menu Bar for \(target?.name ?? "Fullscreen App")"
        customItem.subtitle = available ? "While \(target!.name) is foreground and fullscreen" : "No readable fullscreen app"
        let customMode = target?.bundleID.flatMap { config.rules[$0]?.mode } ?? config.defaultMode
        for item in defaultChoices {
            item.state = item.tag == config.defaultMode?.rawValue ? .on : .off
            item.isEnabled = !preferences.isWriting
        }
        for item in customChoices {
            item.state = available && item.tag == customMode?.rawValue ? .on : .off
            item.isEnabled = available && !preferences.isWriting
        }
        let effective = preferences.currentMode()?.title ?? "Unknown"
        statusItem.button?.toolTip = failure ?? warning ?? "Menu Bar: \(effective)"
        publishSettings()
    }

    private func reconcile(_ context: AppContext, trusted: Bool) {
        guard !reconciling, failure == nil else { refreshMenu(); return }
        reconciling = true
        defer { reconciling = false }
        var config = store.configuration
        do {
            try engine.reconcile(&config, context: context, trusted: trusted) { self.store.recovery = $0 }
            if config != store.configuration {
                store.configuration = config
                publishSettings()
            }
        } catch { fail(error) }
        refreshMenu()
    }
    private func fail(_ error: Error) {
        failure = error.localizedDescription
        publishSettings()
        NSSound.beep()
    }
    @objc private func selectDefault(_ sender: NSMenuItem) {
        guard let mode = MenuBarMode(rawValue: sender.tag) else { return }
        menu.cancelTracking()
        DispatchQueue.main.async { [weak self] in self?.setDefault(mode) }
    }
    private func setDefault(_ mode: MenuBarMode) {
        failure = nil
        var config = store.configuration
        do {
            try engine.setDefault(mode, configuration: &config) { self.store.recovery = $0 }
            store.configuration = config
            publishSettings()
        } catch { fail(error) }
        refreshMenu()
    }
    @objc private func selectCustom(_ sender: NSMenuItem) {
        guard let mode = MenuBarMode(rawValue: sender.tag), let frozen = menuTarget,
              let bundleID = frozen.bundleID else { return }
        menu.cancelTracking()
        DispatchQueue.main.async { [weak self] in
            self?.monitor.readCurrent(includeUnconfigured: true) { [weak self] current, trusted in
                guard let self else { return }
                guard trusted, current.bundleID == bundleID, current.pid == frozen.pid,
                      current.fullscreen == true else {
                    self.warning = "The fullscreen app changed. Reopen the menu to choose it again."
                    self.refreshMenu()
                    NSSound.beep()
                    return
                }
                self.saveRule(AppRule(bundleID: bundleID, name: frozen.name, path: frozen.path, mode: mode), enable: true)
            }
        }
    }
    private func saveRule(_ rule: AppRule, enable: Bool = false) {
        failure = nil
        store.configuration.rules[rule.bundleID] = rule
        if enable { store.configuration.enabled = true }
        configurationChanged()
    }
    private func configurationChanged() {
        failure = nil
        monitor.interestedBundles = store.configuration.enabled ? Set(store.configuration.rules.keys) : []
        publishSettings()
        refreshMenu()
        monitor.schedule()
    }
    private func publishSettings() {
        let loginStatus = SMAppService.mainApp.status
        let snapshot = SettingsSnapshot(configuration: store.configuration, trusted: monitor.trusted,
                                        failure: failure ?? settingsMessage, permissionRequestID: permissionRequestID,
                                        ownerPID: ProcessInfo.processInfo.processIdentifier,
                                        launchAtLogin: loginStatus == .enabled || loginStatus == .requiresApproval,
                                        loginApprovalNeeded: loginStatus == .requiresApproval)
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        SettingsBridge.publish(snapshot)
    }
    private func handleSettingsCommand(_ command: SettingsCommand) {
        switch command {
        case .setDefault(let mode): setDefault(mode)
        case .setEnabled(let enabled):
            store.configuration.enabled = enabled
            configurationChanged()
            if enabled && !monitor.trusted { monitor.requestPermission() }
        case .saveRule(let rule):
            guard !rule.bundleID.isEmpty, rule.bundleID != SettingsBridge.owner,
                  rule.bundleID != "love.oluwaseun.MenuBarToggle.Settings" else { return }
            saveRule(rule)
        case .removeRule(let id):
            store.configuration.rules.removeValue(forKey: id)
            configurationChanged()
        case .requestPermission: monitor.requestPermission()
        case .refreshPermission(let requestID):
            // AXIsProcessTrusted checks this process without prompting. Echo
            // the request so Settings never treats an old snapshot as fresh.
            permissionRequestID = requestID
        case .setMenuBarIcon(let visible):
            store.configuration.showMenuBarIcon = visible
            configurationChanged()
        case .setLaunchAtLogin(let enabled):
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                settingsMessage = nil
            } catch { settingsMessage = "Launch at Login: \(error.localizedDescription)" }
        case .quitApplication:
            NSApp.terminate(nil)
        }
        publishSettings()
    }
    @objc private func showAbout() {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Headroom Settings.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = ["--show-about"]
        NSWorkspace.shared.openApplication(at: helper, configuration: config) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.fail(error) }; return }
            DistributedNotificationCenter.default().postNotificationName(SettingsBridge.showAbout, object: SettingsBridge.owner, userInfo: nil, deliverImmediately: true)
        }
    }
    @objc private func showSettings() {
        publishSettings()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Headroom Settings.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: helper, configuration: config) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.fail(error) } }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        monitor.stop()
        var config = store.configuration
        do {
            try engine.restore(&config) { self.store.recovery = $0 }
            store.configuration = config
            DistributedNotificationCenter.default().postNotificationName(SettingsBridge.quit, object: SettingsBridge.owner, userInfo: nil, deliverImmediately: true)
            return .terminateNow
        } catch {
            fail(error)
            showSettings()
            monitor.start()
            return .terminateCancel
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
