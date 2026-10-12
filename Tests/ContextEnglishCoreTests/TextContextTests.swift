import Foundation
import Testing
@testable import ContextEnglishCore

@Suite("Text language and sentence context")
struct TextContextTests {
    @Test("Detects Chinese, English, and mixed selections")
    func detectsLanguages() {
        #expect(TextLanguageDetector.detect("prioritize") == .english)
        #expect(TextLanguageDetector.detect("推进项目") == .chinese)
        #expect(TextLanguageDetector.detect("推进 roadmap") == .mixed)
        #expect(TextLanguageDetector.detect("123") == .unknown)
    }

    @Test("Extracts the Chinese sentence containing a UTF-16 selection")
    func extractsChineseSentence() {
        let fullText = "上一句。我们需要推进这个项目，确保按计划交付。下一句。"
        let selectedRange = (fullText as NSString).range(of: "推进")
        let result = SentenceContextExtractor.extract(
            from: fullText,
            selectedRangeUTF16: selectedRange
        )

        #expect(result?.text == "我们需要推进这个项目，确保按计划交付。")
        #expect(result?.selectionStartUTF16 == 4)
        #expect(result?.selectionLengthUTF16 == 2)
        #expect(result?.isCompleteSentence == true)
    }

    @Test("Preserves UTF-16 offsets around emoji")
    func preservesUTF16Offsets() {
        let fullText = "Note. 🚀 We should prioritize this work. Done."
        let selectedRange = (fullText as NSString).range(of: "prioritize")
        let result = SentenceContextExtractor.extract(
            from: fullText,
            selectedRangeUTF16: selectedRange
        )

        #expect(result?.text == "🚀 We should prioritize this work.")
        #expect(result?.selectionStartUTF16 == 13)
    }

    @Test("Does not guess context when selection occurs more than once")
    func refusesAmbiguousOccurrence() {
        let result = SentenceContextExtractor.extractUniqueOccurrence(
            of: "issue",
            from: "This issue differs from that issue."
        )
        #expect(result == nil)
    }
}
