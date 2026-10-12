import Foundation

public enum DetectedLanguage: String, Codable, Equatable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"
    case mixed
    case unknown
}

public struct SelectionTextContext: Codable, Equatable, Sendable {
    public let text: String
    public let selectionStartUTF16: Int
    public let selectionLengthUTF16: Int
    public let isCompleteSentence: Bool

    public init(
        text: String,
        selectionStartUTF16: Int,
        selectionLengthUTF16: Int,
        isCompleteSentence: Bool
    ) {
        self.text = text
        self.selectionStartUTF16 = selectionStartUTF16
        self.selectionLengthUTF16 = selectionLengthUTF16
        self.isCompleteSentence = isCompleteSentence
    }
}

public enum TextLanguageDetector {
    public static func detect(_ text: String) -> DetectedLanguage {
        var containsHan = false
        var containsLatin = false

        for scalar in text.unicodeScalars {
            if isHan(scalar.value) {
                containsHan = true
            } else if isLatin(scalar.value) {
                containsLatin = true
            }

            if containsHan && containsLatin {
                return .mixed
            }
        }

        if containsHan { return .chinese }
        if containsLatin { return .english }
        return .unknown
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

    private static func isLatin(_ value: UInt32) -> Bool {
        switch value {
        case 0x0041...0x005A,
             0x0061...0x007A,
             0x00C0...0x024F:
            return true
        default:
            return false
        }
    }
}

public enum SentenceContextExtractor {
    private static let hardBoundaries = CharacterSet(charactersIn: ".!?。！？\n\r")

    /// Extracts the smallest sentence containing a UTF-16 selection range.
    /// Accessibility ranges are expressed in UTF-16, so keeping that coordinate
    /// system avoids corrupting ranges around emoji or non-BMP characters.
    public static func extract(
        from fullText: String,
        selectedRangeUTF16: NSRange,
        maximumLengthUTF16: Int = 800
    ) -> SelectionTextContext? {
        let utf16Count = fullText.utf16.count
        guard selectedRangeUTF16.location >= 0,
              selectedRangeUTF16.length > 0,
              NSMaxRange(selectedRangeUTF16) <= utf16Count,
              let selectedRange = Range(selectedRangeUTF16, in: fullText) else {
            return nil
        }

        var sentenceStart = selectedRange.lowerBound
        while sentenceStart > fullText.startIndex {
            let previous = fullText.index(before: sentenceStart)
            let scalarView = fullText[previous..<sentenceStart].unicodeScalars
            if scalarView.contains(where: { hardBoundaries.contains($0) }) {
                break
            }
            sentenceStart = previous
        }

        var sentenceEnd = selectedRange.upperBound
        var foundTrailingBoundary = false
        while sentenceEnd < fullText.endIndex {
            let next = fullText.index(after: sentenceEnd)
            let scalarView = fullText[sentenceEnd..<next].unicodeScalars
            sentenceEnd = next
            if scalarView.contains(where: { hardBoundaries.contains($0) }) {
                foundTrailingBoundary = true
                break
            }
        }

        let rawSentence = String(fullText[sentenceStart..<sentenceEnd])
        let leadingWhitespace = rawSentence.utf16.prefix {
            guard let scalar = UnicodeScalar($0) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }.count
        let trimmedSentence = rawSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else { return nil }

        let startFromSentence = fullText.utf16.distance(
            from: sentenceStart,
            to: selectedRange.lowerBound
        ) - leadingWhitespace
        guard startFromSentence >= 0 else { return nil }

        let sentenceUTF16Count = trimmedSentence.utf16.count
        guard startFromSentence + selectedRangeUTF16.length <= sentenceUTF16Count else {
            return nil
        }

        if sentenceUTF16Count <= maximumLengthUTF16 {
            return SelectionTextContext(
                text: trimmedSentence,
                selectionStartUTF16: startFromSentence,
                selectionLengthUTF16: selectedRangeUTF16.length,
                isCompleteSentence: foundTrailingBoundary || sentenceEnd == fullText.endIndex
            )
        }

        let selectedEnd = startFromSentence + selectedRangeUTF16.length
        let halfWindow = maximumLengthUTF16 / 2
        var windowStart = max(0, startFromSentence - halfWindow)
        var windowEnd = min(sentenceUTF16Count, windowStart + maximumLengthUTF16)
        if windowEnd < selectedEnd {
            windowEnd = selectedEnd
            windowStart = max(0, windowEnd - maximumLengthUTF16)
        }

        let nsSentence = trimmedSentence as NSString
        let windowText = nsSentence.substring(with: NSRange(
            location: windowStart,
            length: windowEnd - windowStart
        ))
        return SelectionTextContext(
            text: windowText,
            selectionStartUTF16: startFromSentence - windowStart,
            selectionLengthUTF16: selectedRangeUTF16.length,
            isCompleteSentence: false
        )
    }

    /// Safe fallback for controls that expose text but not a numeric selection
    /// range. Context is returned only when the selected string occurs once.
    public static func extractUniqueOccurrence(
        of selectedText: String,
        from fullText: String,
        maximumLengthUTF16: Int = 800
    ) -> SelectionTextContext? {
        guard !selectedText.isEmpty,
              let first = fullText.range(of: selectedText),
              fullText.range(of: selectedText, range: first.upperBound..<fullText.endIndex) == nil else {
            return nil
        }

        let location = fullText.utf16.distance(from: fullText.startIndex, to: first.lowerBound)
        let length = fullText.utf16.distance(from: first.lowerBound, to: first.upperBound)
        return extract(
            from: fullText,
            selectedRangeUTF16: NSRange(location: location, length: length),
            maximumLengthUTF16: maximumLengthUTF16
        )
    }
}
