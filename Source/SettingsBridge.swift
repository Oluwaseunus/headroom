import Foundation
import CoreFoundation

enum SettingsCommand: Codable, Equatable {
    case setDefault(MenuBarMode)
    case setEnabled(Bool)
    case saveRule(AppRule)
    case removeRule(String)
    case requestPermission
    case refreshPermission(String)
    case setLaunchAtLogin(Bool)
    case setMenuBarIcon(Bool)
    case quitApplication
}

struct SettingsSnapshot: Codable, Equatable {
    var configuration: RulesConfiguration
    var trusted: Bool
    var failure: String?
    var permissionRequestID: String? = nil
    var ownerPID: Int32? = nil
    var launchAtLogin: Bool? = nil
    var loginApprovalNeeded: Bool? = nil
}

enum PermissionDisplayState: Equatable {
    case checking, granted, notGranted, unavailable

    static func resolve(snapshot: SettingsSnapshot?, requestID: String?, timedOut: Bool) -> PermissionDisplayState {
        if let snapshot, let requestID, snapshot.permissionRequestID == requestID {
            return snapshot.trusted ? .granted : .notGranted
        }
        return timedOut ? .unavailable : .checking
    }
}

enum PermissionLabels {
    static func paneName(majorVersion: Int) -> String {
        majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
    static func status(_ state: PermissionDisplayState, majorVersion: Int) -> String {
        let value: String
        switch state {
        case .checking: value = "Checking…"
        case .granted: value = "Granted"
        case .notGranted: value = "Not Granted"
        case .unavailable: value = "Unable to Check"
        }
        return "\(paneName(majorVersion: majorVersion)): \(value)"
    }
}

// The menu bar process remains the only writer of rules and system settings.
// Its desktop companion sends small commands and reads acknowledged snapshots.
enum SettingsBridge {
    static let showAbout = Notification.Name("love.oluwaseun.MenuBarToggle.showAbout")
    static let owner = "love.oluwaseun.MenuBarToggle"
    static let command = Notification.Name(owner + ".settingsCommand")
    static let changed = Notification.Name(owner + ".settingsChanged")
    static let quit = Notification.Name(owner + ".quitSettings")
    private static let snapshotKey = "settingsSnapshot.v1"

    static func send(_ value: SettingsCommand) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        DistributedNotificationCenter.default().postNotificationName(command, object: owner,
            userInfo: ["payload": data.base64EncodedString()], deliverImmediately: true)
    }
    static func decode(_ notification: Notification) -> SettingsCommand? {
        guard let payload = notification.userInfo?["payload"] as? String,
              let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(SettingsCommand.self, from: data)
    }
    static func publish(_ value: SettingsSnapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        CFPreferencesSetValue(snapshotKey as CFString, data as CFData, owner as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(owner as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        DistributedNotificationCenter.default().postNotificationName(changed, object: owner, userInfo: nil, deliverImmediately: true)
    }
    static func read() -> SettingsSnapshot? {
        _ = CFPreferencesSynchronize(owner as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard let data = CFPreferencesCopyValue(snapshotKey as CFString, owner as CFString,
                                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data else { return nil }
        return try? JSONDecoder().decode(SettingsSnapshot.self, from: data)
    }
    static func isReady(_ snapshot: SettingsSnapshot?, ownerPID: Int32?) -> Bool {
        guard let ownerPID, ownerPID > 0 else { return false }
        return snapshot?.ownerPID == ownerPID
    }
}
