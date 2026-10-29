import AppKit
import CoreGraphics

struct ConnectedDisplay: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let detail: String
    let builtIn: Bool

    static func current() -> [ConnectedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let mode = CGDisplayCopyDisplayMode(id)
            let width = mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor)
            let height = mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor)
            let size = CGDisplayScreenSize(id)
            let inches = hypot(size.width, size.height) / 25.4
            let sizeText = inches > 1 ? "\(Int(inches.rounded()))-inch · " : ""
            return ConnectedDisplay(id: id, name: screen.localizedName,
                                    detail: "\(sizeText)\(width) × \(height)", builtIn: CGDisplayIsBuiltin(id) != 0)
        }
    }
}
