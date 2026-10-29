import AppKit
import ApplicationServices

private func fullscreenCallback(_ observer: AXObserver, _ element: AXUIElement,
                                _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<FullscreenMonitor>.fromOpaque(context).takeUnretainedValue().schedule()
}

final class FullscreenMonitor {
    var interestedBundles: Set<String> = []
    var didChange: ((AppContext, Bool) -> Void)?
    private(set) var latest = AppContext()
    private let queue = DispatchQueue(label: "MenuBarToggle.fullscreen", qos: .userInitiated)
    private var workspaceTokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var manualGeneration = 0
    private var sessionActive = true
    private var observer: AXObserver?
    private var observedPID: pid_t = -1
    var trusted: Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
    }

    func start() {
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.willSleepNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if name == NSWorkspace.sessionDidResignActiveNotification || name == NSWorkspace.willSleepNotification { self.sessionActive = false }
                if name == NSWorkspace.sessionDidBecomeActiveNotification || name == NSWorkspace.didWakeNotification { self.sessionActive = true }
                self.schedule()
            })
        }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer!, forMode: .common)
        sample()
    }
    func schedule() {
        pending?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.sample() }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }
    func requestPermission() {
        // This remains the AX permission pane, renamed Device Control and
        // Data Access on macOS 27. Opening it does not grant permission.
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        schedule()
    }

    func readCurrent(includeUnconfigured: Bool = false, _ completion: @escaping (AppContext, Bool) -> Void) {
        if includeUnconfigured { manualGeneration += 1 } else { generation += 1 }
        let request = includeUnconfigured ? manualGeneration : generation
        guard sessionActive else { completion(AppContext(bundleID: ""), trusted); return }
        let active = NSWorkspace.shared.frontmostApplication
        let allowed = trusted
        let context = AppContext(bundleID: active?.bundleIdentifier, name: active?.localizedName ?? "App",
                                 path: active?.bundleURL?.path ?? "", pid: active?.processIdentifier ?? -1)
        guard allowed, context.pid > 0, let bundle = context.bundleID,
              (interestedBundles.contains(bundle) || includeUnconfigured) else {
            attachObserver(nil)
            completion(context, allowed)
            return
        }
        attachObserver(context.pid)
        queue.async { [weak self] in
            var result = context
            let app = AXUIElementCreateApplication(context.pid)
            AXUIElementSetMessagingTimeout(app, 0.35)
            var focused: CFTypeRef?
            let windowCode = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
            if windowCode == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let window = unsafeBitCast(focused, to: AXUIElement.self)
                var value: CFTypeRef?
                let code = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
                if code == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() {
                    result.fullscreen = (value as! NSNumber).boolValue
                }
            }
            let completed = result
            DispatchQueue.main.async {
                guard let self, self.sessionActive,
                      (includeUnconfigured ? self.manualGeneration : self.generation) == request,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == context.pid else { return }
                completion(completed, self.trusted)
            }
        }
    }
    private func sample() {
        readCurrent { [weak self] context, trusted in
            self?.latest = context
            self?.didChange?(context, trusted)
        }
    }
    private func attachObserver(_ pid: pid_t?) {
        guard pid != observedPID else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedPID = -1
        guard let pid else { return }
        var value: AXObserver?
        guard AXObserverCreate(pid, fullscreenCallback, &value) == .success, let value else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        for name in ["AXFocusedWindowChanged", "AXMainWindowChanged", "AXWindowResized", "AXUIElementDestroyed"] {
            _ = AXObserverAddNotification(value, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        observer = value
        observedPID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(value), .commonModes)
    }
    func stop() {
        generation += 1
        manualGeneration += 1
        timer?.invalidate()
        pending?.cancel()
        attachObserver(nil)
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
    }
}
