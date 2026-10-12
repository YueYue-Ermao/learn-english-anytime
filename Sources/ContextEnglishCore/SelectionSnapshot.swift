import CoreGraphics
import Foundation

public enum SelectionSource: String, Codable, Sendable {
    case macOSAccessibility = "macos_accessibility"
    case browserExtension = "browser_extension"
    case internalComposer = "internal_composer"
    case explicitClipboard = "explicit_clipboard"
}

public enum SurfaceKind: String, Codable, Sendable {
    case readOnly
    case editable
    case unknown
}

public struct SelectionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let bounds: CGRect?
    public let source: SelectionSource
    public let sourceApplicationID: String?
    public let surfaceKind: SurfaceKind
    public let language: DetectedLanguage
    public let context: SelectionTextContext?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        bounds: CGRect?,
        source: SelectionSource,
        sourceApplicationID: String?,
        surfaceKind: SurfaceKind,
        language: DetectedLanguage? = nil,
        context: SelectionTextContext? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.bounds = bounds
        self.source = source
        self.sourceApplicationID = sourceApplicationID
        self.surfaceKind = surfaceKind
        self.language = language ?? TextLanguageDetector.detect(text)
        self.context = context
        self.createdAt = createdAt
    }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
