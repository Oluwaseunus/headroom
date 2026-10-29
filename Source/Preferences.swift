import Foundation
import CoreFoundation

enum MenuBarMode: Int, CaseIterable, Codable {
    case always = 0, desktopOnly, fullScreenOnly, never

    var title: String {
        switch self {
        case .always: return "Always"
        case .desktopOnly: return "On Desktop Only"
        case .fullScreenOnly: return "In Full Screen Only"
        case .never: return "Never"
        }
    }
    // Settings describes showing the menu bar; macOS stores auto-hide modes.
    static let visibilityOrder: [MenuBarMode] = [.never, .fullScreenOnly, .desktopOnly, .always]
    var visibilityTitle: String {
        switch self {
        case .never: return "Always"
        case .fullScreenOnly: return "On Desktop Only"
        case .desktopOnly: return "In Full Screen Only"
        case .always: return "Never"
        }
    }
    var desktopHidden: Bool { self == .always || self == .desktopOnly }
    var fullScreenVisible: Bool { self == .desktopOnly || self == .never }
    var values: [NSNumber] {
        [NSNumber(value: desktopHidden), NSNumber(value: fullScreenVisible), NSNumber(value: rawValue)]
    }
    static func resolve(_ values: [NSNumber?]) -> MenuBarMode? {
        guard values.count == 3, let desktop = values[0], let fullscreen = values[1],
              let option = values[2], option.doubleValue == Double(option.intValue),
              let mode = MenuBarMode(rawValue: option.intValue),
              [0, 1].contains(desktop.intValue), desktop.doubleValue == Double(desktop.intValue),
              [0, 1].contains(fullscreen.intValue), fullscreen.doubleValue == Double(fullscreen.intValue),
              desktop.boolValue == mode.desktopHidden,
              fullscreen.boolValue == mode.fullScreenVisible else { return nil }
        return mode
    }
}

protocol PreferenceAccess {
    func read() -> [Any?]
    func write(_ values: [Any?]) throws
    func notify()
}

enum PreferenceError: LocalizedError {
    case write, verification, rollback, stateUnavailable
    var errorDescription: String? {
        switch self {
        case .write: return "macOS could not save the menu bar setting."
        case .verification: return "macOS did not retain the requested setting. Your previous values were restored."
        case .rollback: return "The change failed and the previous values could not be fully restored. Check Menu Bar in System Settings."
        case .stateUnavailable: return "The current menu bar setting could not be read. Automatic changes are paused."
        }
    }
}

final class MenuBarPreferences {
    let access: PreferenceAccess
    private(set) var isWriting = false
    init(access: PreferenceAccess = SystemPreferences()) { self.access = access }
    func currentMode() -> MenuBarMode? {
        MenuBarMode.resolve(access.read().map { $0 as? NSNumber })
    }
    func apply(_ mode: MenuBarMode) throws {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        let original = access.read()
        do {
            try access.write(mode.values.map { $0 as Any? })
            access.notify()
            guard currentMode() == mode else { throw PreferenceError.verification }
        } catch {
            do {
                try access.write(original)
                access.notify()
                guard Self.equal(original, access.read()) else { throw PreferenceError.rollback }
            } catch { throw PreferenceError.rollback }
            throw error
        }
    }
    private static func equal(_ lhs: [Any?], _ rhs: [Any?]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { a, b in
            switch (a, b) {
            case (nil, nil): return true
            case (let a?, let b?): return NSDictionary(dictionary: ["value": a]).isEqual(to: ["value": b])
            default: return false
            }
        }
    }
}

final class SystemPreferences: PreferenceAccess {
    static let notifications = ["AppleInterfaceMenuBarHidingChangedNotification", "AppleInterfaceFullScreenMenuBarVisibilityChangedNotification"]
    private let keys = ["_HIHideMenuBar", "AppleMenuBarVisibleInFullscreen", "AutoHideMenuBarOption"]
    private func domain(_ index: Int) -> CFString {
        index < 2 ? kCFPreferencesAnyApplication : "com.apple.controlcenter" as CFString
    }
    func read() -> [Any?] {
        // Refresh the explicit domains before reading changes made by System Settings.
        for index in [0, 2] {
            _ = CFPreferencesSynchronize(domain(index), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        return keys.indices.map {
            CFPreferencesCopyValue(keys[$0] as CFString, domain($0), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
    }
    func write(_ values: [Any?]) throws {
        guard values.count == keys.count else { throw PreferenceError.write }
        for index in keys.indices {
            CFPreferencesSetValue(keys[index] as CFString, values[index] as CFPropertyList?, domain(index),
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        for index in [0, 2] {
            guard CFPreferencesSynchronize(domain(index), kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
                throw PreferenceError.write
            }
        }
    }
    func notify() {
        for name in Self.notifications {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
        }
    }
}
