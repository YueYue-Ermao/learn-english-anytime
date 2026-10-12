import AppKit

enum AppVisualTheme {
    static let accent = NSColor(
        calibratedRed: 91.0 / 255.0,
        green: 86.0 / 255.0,
        blue: 214.0 / 255.0,
        alpha: 1
    )
    static let accentSoft = NSColor(
        calibratedRed: 111.0 / 255.0,
        green: 105.0 / 255.0,
        blue: 230.0 / 255.0,
        alpha: 0.14
    )
    static let success = NSColor.systemGreen
    static let warning = NSColor.systemOrange

    static var surface: NSColor {
        dynamicColor(
            light: NSColor(calibratedWhite: 1, alpha: 0.94),
            dark: NSColor(calibratedRed: 24.0 / 255.0, green: 27.0 / 255.0, blue: 39.0 / 255.0, alpha: 0.96)
        )
    }

    static var raisedSurface: NSColor {
        dynamicColor(
            light: NSColor(calibratedRed: 246.0 / 255.0, green: 247.0 / 255.0, blue: 252.0 / 255.0, alpha: 0.96),
            dark: NSColor(calibratedRed: 38.0 / 255.0, green: 41.0 / 255.0, blue: 56.0 / 255.0, alpha: 0.96)
        )
    }

    static var border: NSColor {
        dynamicColor(
            light: NSColor(calibratedWhite: 0.12, alpha: 0.10),
            dark: NSColor(calibratedWhite: 1, alpha: 0.12)
        )
    }

    static func symbol(_ name: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        return image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        )
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

final class RoundedSurfaceView: NSView {
    private let fillColor: NSColor
    private let strokeColor: NSColor
    private let radius: CGFloat

    init(
        fillColor: NSColor = AppVisualTheme.raisedSurface,
        strokeColor: NSColor = AppVisualTheme.border,
        radius: CGFloat = 12
    ) {
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
        updateLayerColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
            layer?.borderColor = strokeColor.cgColor
        }
        layer?.borderWidth = 1
    }
}
