import AppKit

enum ScreenCoordinateConverter {
    /// Accessibility bounds use a top-left origin. AppKit windows use a
    /// bottom-left origin. This conversion is correct for the primary display
    /// and common horizontally-arranged display layouts; the result is
    /// validated before use and falls back to the pointer when unavailable.
    static func appKitRect(fromAccessibilityRect rect: CGRect) -> CGRect? {
        guard rect.isFinite,
              rect.width >= 0,
              rect.height >= 0,
              let primaryScreen = primaryScreen else {
            return nil
        }

        let converted = CGRect(
            x: rect.minX,
            y: primaryScreen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let visibleUnion = NSScreen.screens
            .map(\.visibleFrame)
            .reduce(CGRect.null) { $0.union($1) }

        return visibleUnion.intersects(converted) ? converted : nil
    }

    private static var primaryScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == CGMainDisplayID()
        } ?? NSScreen.main
    }
}

private extension CGRect {
    var isFinite: Bool {
        [minX, minY, width, height].allSatisfy(\.isFinite)
    }
}
