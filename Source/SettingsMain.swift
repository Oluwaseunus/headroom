import AppKit

private final class DesktopSettingsDelegate: NSObject, NSApplicationDelegate {
    private var controller: SettingsWindowController!
    private var snapshot: SettingsSnapshot?
    private var tokens: [NSObjectProtocol] = []
    private var permissionRequestID: String?
    private var permissionTimedOut = false
    private var permissionTimeout: DispatchWorkItem?
    private var permissionRequestSent = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count > 1 {
            NSApp.terminate(nil); return
        }
        snapshot = SettingsBridge.read()
        controller = SettingsWindowController(configuration: { [weak self] in self?.snapshot?.configuration ?? RulesConfiguration() },
                                              permissionState: { [weak self] in self?.permissionState ?? .checking },
                                              loginState: { [weak self] in (self?.snapshot?.launchAtLogin, self?.snapshot?.loginApprovalNeeded ?? false) })
        controller.onLaunchAtLogin = { SettingsBridge.send(.setLaunchAtLogin($0)) }
        controller.onShowIcon = { SettingsBridge.send(.setMenuBarIcon($0)) }
        controller.onDefault = { SettingsBridge.send(.setDefault($0)) }
        controller.onEnabled = { SettingsBridge.send(.setEnabled($0)) }
        controller.onSaveRule = { SettingsBridge.send(.saveRule($0)) }
        controller.onRemoveRule = { SettingsBridge.send(.removeRule($0)) }
        controller.onPermission = { [weak self] in
            if self?.permissionState == .unavailable { self?.requestFreshPermission() }
            else { SettingsBridge.send(.requestPermission) }
        }
        controller.onClose = { NSApp.terminate(nil) }
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(forName: SettingsBridge.changed, object: SettingsBridge.owner, queue: .main) { [weak self] _ in self?.refresh() })
        tokens.append(center.addObserver(forName: SettingsBridge.quit, object: SettingsBridge.owner, queue: .main) { _ in NSApp.terminate(nil) })
        installMenu()
        show()
    }
    private func refresh() {
        guard let updated = SettingsBridge.read(), updated != snapshot else { return }
        snapshot = updated
        sendPermissionRequestIfReady()
        if updated.permissionRequestID == permissionRequestID { permissionTimeout?.cancel() }
        controller.reload(message: updated.failure)
    }
    private func show() {
        requestFreshPermission()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
    private var permissionState: PermissionDisplayState {
        PermissionDisplayState.resolve(snapshot: snapshot, requestID: permissionRequestID, timedOut: permissionTimedOut)
    }
    private func requestFreshPermission() {
        let requestID = UUID().uuidString
        permissionRequestID = requestID
        permissionTimedOut = false
        permissionRequestSent = false
        permissionTimeout?.cancel()
        controller.refreshPermission()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.permissionRequestID == requestID else { return }
            self.refresh()
            self.permissionTimedOut = true
            self.controller.refreshPermission()
        }
        permissionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        ensureMenuBarAppRunning { [weak self] in
            guard self?.permissionRequestID == requestID else { return }
            self?.sendPermissionRequestIfReady()
        }
    }
    private func sendPermissionRequestIfReady() {
        guard !permissionRequestSent, let permissionRequestID else { return }
        let ownerPID = NSRunningApplication.runningApplications(withBundleIdentifier: SettingsBridge.owner).first?.processIdentifier
        // The owner publishes its PID only after registering the receiver.
        // A snapshot from an earlier process cannot satisfy this handshake.
        guard SettingsBridge.isReady(SettingsBridge.read(), ownerPID: ownerPID) else { return }
        permissionRequestSent = true
        SettingsBridge.send(.refreshPermission(permissionRequestID))
    }
    private func installMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Settings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let quitMain = NSMenuItem(title: "Quit Menu Bar Toggle", action: #selector(quitMenuBarApp), keyEquivalent: "")
        quitMain.target = self
        appMenu.addItem(quitMain)
        app.submenu = appMenu
        menu.addItem(app)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        file.submenu = fileMenu
        menu.addItem(file)
        NSApp.mainMenu = menu
    }
    @objc private func quitMenuBarApp() { SettingsBridge.send(.quitApplication) }
    private func ensureMenuBarAppRunning(completion: @escaping () -> Void) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: SettingsBridge.owner).isEmpty else { completion(); return }
        let ownerURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: ownerURL, configuration: config) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { completion() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
private enum SettingsEntry {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = DesktopSettingsDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
