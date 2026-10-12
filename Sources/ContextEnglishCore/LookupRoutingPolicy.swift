import Foundation

public enum LookupRoute: Equatable, Sendable {
    case localDictionaryFirst
    case modelRecommended
}

/// Keeps ordinary lexical lookup offline while routing longer or contextual
/// expressions to the explicit model action. This policy never starts a model
/// request; it only decides whether a local dictionary lookup is worthwhile.
public struct LookupRoutingPolicy: Sendable {
    private static let sentencePunctuation = CharacterSet(charactersIn: ".!?。！？；;\n\r")

    public init() {}

    public func route(for text: String, language: DetectedLanguage) -> LookupRoute {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: { Self.sentencePunctuation.contains($0) }) else {
            return .modelRecommended
        }

        switch language {
        case .english:
            let words = value.split { character in
                character.isWhitespace || character == "/"
            }
            return words.count <= 4 && value.count <= 48
                ? .localDictionaryFirst
                : .modelRecommended

        case .chinese:
            let hanCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
                if Self.isHan(scalar.value) { count += 1 }
            }
            let containsWhitespace = value.contains(where: \.isWhitespace)
            return !containsWhitespace && hanCount > 0 && hanCount <= 8
                ? .localDictionaryFirst
                : .modelRecommended

        case .mixed, .unknown:
            return .modelRecommended
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
