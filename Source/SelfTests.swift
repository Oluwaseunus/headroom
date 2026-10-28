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
    print("Passed \(checks) checks. No system preferences were changed.")
}
