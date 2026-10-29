import Foundation

struct AppRule: Codable, Equatable {
    let bundleID: String
    var name: String
    var path: String
    var mode: MenuBarMode
}

struct RulesConfiguration: Codable, Equatable {
    var defaultMode: MenuBarMode?
    var enabled = true
    var rules: [String: AppRule] = [:]
    var showMenuBarIcon = true

    init(defaultMode: MenuBarMode? = nil, enabled: Bool = true, rules: [String: AppRule] = [:], showMenuBarIcon: Bool = true) {
        self.defaultMode = defaultMode
        self.enabled = enabled
        self.rules = rules
        self.showMenuBarIcon = showMenuBarIcon
    }
    private enum CodingKeys: String, CodingKey { case defaultMode, enabled, rules, showMenuBarIcon }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultMode = try values.decodeIfPresent(MenuBarMode.self, forKey: .defaultMode)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let stored = try values.decodeIfPresent([String: StoredRule].self, forKey: .rules) ?? [:]
        // Old "Use Default" rows carry no override, so migrate them away.
        rules = stored.compactMapValues { rule in
            guard let mode = rule.mode else { return nil }
            return AppRule(bundleID: rule.bundleID, name: rule.name, path: rule.path, mode: mode)
        }
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    }
    private struct StoredRule: Decodable {
        let bundleID: String
        let name: String
        let path: String
        let mode: MenuBarMode?
    }
}

struct AppContext: Equatable {
    var bundleID: String?
    var name: String = "App"
    var path: String = ""
    var pid: Int32 = -1
    // nil means unavailable or permission denied, rather than windowed.
    var fullscreen: Bool?
}

struct OverrideRecovery: Codable {
    let baseline: MenuBarMode
    let applied: MenuBarMode
}

final class RulesStore {
    private let defaults: UserDefaults
    var configuration: RulesConfiguration {
        didSet { if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: "appRules.v1") } }
    }
    var recovery: OverrideRecovery? {
        get {
            guard let data = defaults.data(forKey: "overrideRecovery.v1") else { return nil }
            return try? JSONDecoder().decode(OverrideRecovery.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: "overrideRecovery.v1")
            } else { defaults.removeObject(forKey: "overrideRecovery.v1") }
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "appRules.v1"),
           let saved = try? JSONDecoder().decode(RulesConfiguration.self, from: data) {
            configuration = saved
        } else { configuration = RulesConfiguration() }
    }
}

enum RuleDecision: Equatable {
    case useDefault, useRule(MenuBarMode), unknown
    static func resolve(_ configuration: RulesConfiguration, context: AppContext, trusted: Bool) -> RuleDecision {
        guard configuration.enabled, trusted else { return .useDefault }
        guard let bundleID = context.bundleID else { return .unknown }
        guard let rule = configuration.rules[bundleID] else { return .useDefault }
        guard let fullscreen = context.fullscreen else { return .unknown }
        return fullscreen ? .useRule(rule.mode) : .useDefault
    }
}

// This controller only owns writes while a rule is active. It adopts external
// changes as the default, rather than imposing a stored default every timer tick.
final class RuleEngine {
    private let preferences: MenuBarPreferences
    private(set) var overrideBundleID: String?
    private(set) var overrideMode: MenuBarMode?
    init(preferences: MenuBarPreferences) { self.preferences = preferences }

    func reconcile(_ configuration: inout RulesConfiguration, context: AppContext, trusted: Bool,
                   willWrite: (OverrideRecovery?) -> Void) throws {
        let actual = preferences.currentMode()
        if configuration.defaultMode == nil { configuration.defaultMode = actual }
        // An unknown baseline must never be replaced with a guessed default.
        guard let baseline = configuration.defaultMode else { return }
        let decision = RuleDecision.resolve(configuration, context: context, trusted: trusted)
        if case .unknown = decision, overrideBundleID == context.bundleID { return }

        if case .useRule(let mode) = decision {
            if let previous = overrideMode, let actual, actual != previous {
                configuration.defaultMode = actual
            } else if overrideMode == nil, let actual {
                configuration.defaultMode = actual
            }
            guard actual != nil else { return }
            let restoreMode = configuration.defaultMode ?? baseline
            willWrite(OverrideRecovery(baseline: restoreMode, applied: mode))
            if actual != mode { try preferences.apply(mode) }
            overrideBundleID = context.bundleID
            overrideMode = mode
            return
        }

        if let previous = overrideMode {
            // If another actor changed the preference, preserve that change.
            if actual == previous {
                guard baseline != actual else { clear(willWrite); return }
                try preferences.apply(baseline)
            } else if let actual { configuration.defaultMode = actual }
            else { return }
            clear(willWrite)
        } else if let actual { configuration.defaultMode = actual }
    }

    func setDefault(_ mode: MenuBarMode, configuration: inout RulesConfiguration,
                    willWrite: (OverrideRecovery?) -> Void) throws {
        if let applied = overrideMode {
            configuration.defaultMode = mode
            willWrite(OverrideRecovery(baseline: mode, applied: applied))
        } else {
            if preferences.currentMode() != mode { try preferences.apply(mode) }
            configuration.defaultMode = mode
            willWrite(nil)
        }
    }

    func restore(_ configuration: inout RulesConfiguration, willWrite: (OverrideRecovery?) -> Void) throws {
        try reconcile(&configuration, context: AppContext(bundleID: ""), trusted: false, willWrite: willWrite)
        guard overrideMode == nil else { throw PreferenceError.stateUnavailable }
    }
    private func clear(_ willWrite: (OverrideRecovery?) -> Void) {
        overrideBundleID = nil
        overrideMode = nil
        willWrite(nil)
    }
}
