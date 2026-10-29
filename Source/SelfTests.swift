import Foundation

private final class FakePreferences: PreferenceAccess {
    var values: [Any?] = [nil, nil, nil]
    var failNextWrite = false
    var notifications = 0
    func read() -> [Any?] { values }
    func write(_ newValues: [Any?]) throws {
        values[0] = newValues[0]
        if failNextWrite { failNextWrite = false; throw PreferenceError.write }
        values = newValues
    }
    func notify() { notifications += 1 }
}

func runSelfTests() {
    var checks = 0
    func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        checks += 1
    }
    let expected = [(true, false), (true, true), (false, false), (false, true)]
    for mode in MenuBarMode.allCases {
        check(mode.desktopHidden == expected[mode.rawValue].0 && mode.fullScreenVisible == expected[mode.rawValue].1, "mode mapping")
        check(MenuBarMode.resolve(mode.values) == mode, "mode resolution")
    }
    let visibility = MenuBarMode.visibilityOrder
    check(visibility.map(\.visibilityTitle) == ["Always", "On Desktop Only", "In Full Screen Only", "Never"], "visibility control order")
    let shownStates = [(true, true), (true, false), (false, true), (false, false)]
    for (index, mode) in visibility.enumerated() {
        check(!mode.desktopHidden == shownStates[index].0 && mode.fullScreenVisible == shownStates[index].1,
              "show labels preserve the inverse macOS hide behaviour")
    }
    check(MenuBarMode.resolve([nil, nil, nil]) == nil, "missing keys")
    check(MenuBarMode.resolve([0, 0, 3]) == nil, "conflicting keys")
    check(MenuBarMode.resolve([0, 1, 9]) == nil, "invalid enum")
    check(MenuBarMode.resolve([2, 1, 3]) == nil, "invalid boolean")
    let fake = FakePreferences()
    let store = MenuBarPreferences(access: fake)
    do {
        try store.apply(.always)
        check(store.currentMode() == .always && fake.notifications == 1, "apply and notify")
        fake.values = [nil, NSNumber(value: false), nil]
        fake.failNextWrite = true
        do { try store.apply(.never); check(false, "failure must propagate") }
        catch {
            check(fake.values[0] == nil && fake.values[2] == nil && (fake.values[1] as? NSNumber)?.boolValue == false, "exact rollback with absent values")
            check(!store.isWriting, "write guard released after error")
        }
    } catch { check(false, "unexpected error: \(error)") }
    let app = "test.brave"
    let second = "test.video"
    var config = RulesConfiguration(defaultMode: .never)
    config.rules[app] = AppRule(bundleID: app, name: "Brave", path: "/example/Brave.app", mode: .always)
    config.rules[second] = AppRule(bundleID: second, name: "Video", path: "/example/Video.app", mode: .desktopOnly)
    let fullscreen = AppContext(bundleID: app, fullscreen: true)
    check(RuleDecision.resolve(config, context: fullscreen, trusted: true) == .useRule(.always), "matching fullscreen app")
    check(RuleDecision.resolve(config, context: AppContext(bundleID: app, fullscreen: false), trusted: true) == .useDefault, "windowed app")
    check(RuleDecision.resolve(config, context: AppContext(bundleID: "other"), trusted: true) == .useDefault, "unmatched app")
    check(RuleDecision.resolve(config, context: AppContext(bundleID: app), trusted: true) == .unknown, "failed AX read stays unknown")
    check(RuleDecision.resolve(config, context: fullscreen, trusted: false) == .useDefault, "permission loss")
    var disabled = config
    disabled.enabled = false
    check(RuleDecision.resolve(disabled, context: fullscreen, trusted: true) == .useDefault, "disabled automation")
    let memory = FakePreferences()
    memory.values = MenuBarMode.never.values
    let rulePreferences = MenuBarPreferences(access: memory)
    let engine = RuleEngine(preferences: rulePreferences)
    var recovery: OverrideRecovery?
    do {
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .always && engine.overrideBundleID == app, "enter fullscreen applies rule")
        check(config.defaultMode == .never && recovery?.baseline == .never, "preserve default while overridden")
        let notificationCount = memory.notifications
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        check(memory.notifications == notificationCount, "stable context avoids repeated writes")
        try engine.reconcile(&config, context: AppContext(bundleID: app), trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .always, "transient unknown in same app preserves state")
        try engine.reconcile(&config, context: AppContext(bundleID: second), trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .never && engine.overrideMode == nil, "different unknown app restores default")
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        try engine.setDefault(.fullScreenOnly, configuration: &config) { recovery = $0 }
        check(rulePreferences.currentMode() == .always && config.defaultMode == .fullScreenOnly, "default edit preserves active rule")
        check(recovery?.baseline == .fullScreenOnly, "recovery tracks edited default")
        try engine.reconcile(&config, context: AppContext(bundleID: second, fullscreen: true), trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .desktopOnly && config.defaultMode == .fullScreenOnly, "switching matching apps preserves baseline")
        try engine.reconcile(&config, context: AppContext(bundleID: second, fullscreen: false), trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .fullScreenOnly && recovery == nil, "exit fullscreen restores and clears recovery")
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        try engine.reconcile(&config, context: fullscreen, trusted: false) { recovery = $0 }
        check(rulePreferences.currentMode() == .fullScreenOnly && engine.overrideMode == nil, "permission revoked restores default")
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        config.rules.removeValue(forKey: app)
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        check(rulePreferences.currentMode() == .fullScreenOnly, "deleting active rule restores default")
        memory.values = MenuBarMode.never.values
        let externalNotificationCount = memory.notifications
        try engine.reconcile(&config, context: AppContext(bundleID: "other"), trusted: true) { recovery = $0 }
        check(config.defaultMode == .never && memory.notifications == externalNotificationCount, "external default edit is adopted without writing")
        config.rules[app] = AppRule(bundleID: app, name: "Brave", path: "", mode: .always)
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        memory.values = MenuBarMode.desktopOnly.values
        try engine.restore(&config) { recovery = $0 }
        check(rulePreferences.currentMode() == .desktopOnly && config.defaultMode == .desktopOnly, "quit preserves different external choice")
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        try engine.restore(&config) { recovery = $0 }
        check(rulePreferences.currentMode() == .desktopOnly && recovery == nil, "quit restores an owned override")
        memory.values = [nil, nil, nil]
        let before = memory.notifications
        try engine.reconcile(&config, context: fullscreen, trusted: true) { recovery = $0 }
        check(memory.notifications == before && engine.overrideMode == nil, "unknown preferences cause no guessed writes")
        let encoded = try JSONEncoder().encode(config)
        check(try JSONDecoder().decode(RulesConfiguration.self, from: encoded) == config, "configuration roundtrip")
        let commands: [SettingsCommand] = [.setDefault(.never), .setEnabled(false), .saveRule(config.rules[app]!), .removeRule(app), .requestPermission, .refreshPermission("fresh-request"), .setLaunchAtLogin(false), .setMenuBarIcon(true), .quitApplication]
        for command in commands {
            let data = try JSONEncoder().encode(command)
            let note = Notification(name: SettingsBridge.command, userInfo: ["payload": data.base64EncodedString()])
            check(SettingsBridge.decode(note) == command, "desktop companion command roundtrip")
        }
        check(SettingsBridge.decode(Notification(name: SettingsBridge.command, userInfo: ["payload": "invalid"])) == nil, "malformed companion command rejected")
        let snapshot = SettingsSnapshot(configuration: config, trusted: true, failure: nil)
        check(try JSONDecoder().decode(SettingsSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot, "desktop companion snapshot roundtrip")
        check(PermissionDisplayState.resolve(snapshot: snapshot, requestID: "new", timedOut: false) == .checking, "cached permission cannot be shown as a fresh result")
        var permissionSnapshot = snapshot
        permissionSnapshot.permissionRequestID = "new"
        check(PermissionDisplayState.resolve(snapshot: permissionSnapshot, requestID: "new", timedOut: false) == .granted, "fresh granted permission hides setup action")
        permissionSnapshot.trusted = false
        check(PermissionDisplayState.resolve(snapshot: permissionSnapshot, requestID: "new", timedOut: false) == .notGranted, "fresh denied permission offers setup")
        check(PermissionDisplayState.resolve(snapshot: permissionSnapshot, requestID: "reopened", timedOut: false) == .checking, "reopening requires another fresh check")
        check(PermissionDisplayState.resolve(snapshot: permissionSnapshot, requestID: "reopened", timedOut: true) == .unavailable, "missing response is not mistaken for denied permission")
        permissionSnapshot.ownerPID = 123
        check(SettingsBridge.isReady(permissionSnapshot, ownerPID: 123), "current process readiness acknowledged")
        check(!SettingsBridge.isReady(permissionSnapshot, ownerPID: 124), "previous process snapshot cannot acknowledge startup")
        check(!SettingsBridge.isReady(permissionSnapshot, ownerPID: nil), "stopped process cannot acknowledge startup")
        check(PermissionLabels.paneName(majorVersion: 26) == "Accessibility", "older macOS permission name")
        check(PermissionLabels.paneName(majorVersion: 27) == "Device Control and Data Access", "macOS 27 permission name")
        check(PermissionLabels.status(.granted, majorVersion: 27).hasSuffix(": Granted"), "granted state is explicit")
        check(PermissionLabels.status(.notGranted, majorVersion: 27).hasSuffix(": Not Granted"), "ungranted state is explicit")
        let legacy = Data("{\"defaultMode\":3,\"enabled\":false,\"rules\":{\"legacy.app\":{\"bundleID\":\"legacy.app\",\"name\":\"Legacy\",\"path\":\"/Legacy.app\",\"mode\":0}}}".utf8)
        let migrated = try JSONDecoder().decode(RulesConfiguration.self, from: legacy)
        check(migrated.defaultMode == .never && !migrated.enabled && migrated.showMenuBarIcon, "existing configuration preserves defaults and starts with visible icon")
        check(migrated.rules["legacy.app"]?.mode == .always, "existing app rule modes migrate")
        let inheritedData = Data("{\"defaultMode\":3,\"rules\":{\"inherited.app\":{\"bundleID\":\"inherited.app\",\"name\":\"Inherited\",\"path\":\"\"}}}".utf8)
        let cleaned = try JSONDecoder().decode(RulesConfiguration.self, from: inheritedData)
        check(cleaned.rules.isEmpty && cleaned.defaultMode == .never, "legacy inherited rows migrate to following default without a rule")
        check(MenuBarMode.allCases.count == 4, "per-app modes contain only the four explicit choices")

    } catch { check(false, "rule engine error: \(error)") }
    print("Passed \(checks) checks. No system preferences were changed.")
}
