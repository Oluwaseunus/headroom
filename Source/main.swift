import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = MenuBarPreferences()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var modeItems: [NSMenuItem] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var failure: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "love.oluwaseun.MenuBarToggle").count <= 1 else {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.setAccessibilityLabel("Menu Bar Toggle")
        let modeMenu = NSMenu()
        for mode in MenuBarMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.tag = mode.rawValue
            item.target = self
            modeMenu.addItem(item)
            modeItems.append(item)
        }
        let modeItem = NSMenuItem(title: "Hide Menu Bar", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Menu Bar Toggle", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        for name in SystemPreferences.notifications {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        let mode = preferences.currentMode()
        for item in modeItems {
            item.state = item.tag == mode?.rawValue ? .on : .off
            item.isEnabled = !preferences.isWriting
        }
        let image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu Bar Toggle")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = failure ?? "Menu Bar: \(mode?.title ?? "Unknown")"
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = MenuBarMode(rawValue: sender.tag) else { return }
        apply(mode)
    }
    private func apply(_ mode: MenuBarMode) {
        menu.cancelTracking()
        // Let menu tracking end before applying, so pointer/menu reveal does not obscure the change.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do { try self.preferences.apply(mode); self.failure = nil }
            catch { self.failure = error.localizedDescription; NSSound.beep() }
            self.refresh()
        }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
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
