import Foundation

/// Decides when a selection should move directly from lookup to an on-device
/// translation. The policy deliberately excludes single unknown words so a
/// typo does not start a language download or replace the dictionary result.
public struct AutomaticTranslationPolicy: Sendable {
    public let maximumCharacterCount: Int

    public init(maximumCharacterCount: Int = 280) {
        self.maximumCharacterCount = maximumCharacterCount
    }

    public func shouldTranslate(
        text: String,
        language: DetectedLanguage,
        route: LookupRoute,
        hasLocalEntry: Bool,
        serviceAvailable: Bool
    ) -> Bool {
        guard serviceAvailable, !hasLocalEntry else { return false }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumCharacterCount else { return false }

        if route == .modelRecommended {
            return true
        }

        switch language {
        case .english:
            return value.split(whereSeparator: { $0.isWhitespace }).count >= 2
        case .chinese:
            let hanCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
                if Self.isHan(scalar.value) { count += 1 }
            }
            return hanCount >= 3
        case .mixed:
            return true
        case .unknown:
            return value.contains(where: \.isWhitespace)
        }
    }

    private static func isHan(_ value: UInt32) -> Bool {
        switch value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }
}
