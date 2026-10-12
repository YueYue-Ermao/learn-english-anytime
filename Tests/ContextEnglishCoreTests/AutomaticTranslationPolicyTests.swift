import Testing
@testable import ContextEnglishCore

@Suite("Automatic on-device translation policy")
struct AutomaticTranslationPolicyTests {
    private let policy = AutomaticTranslationPolicy()

    @Test("Short sentences and phrases translate automatically when on-device translation exists")
    func expressionsTranslateAutomatically() {
        #expect(policy.shouldTranslate(
            text: "I will follow up tomorrow.",
            language: .english,
            route: .modelRecommended,
            hasLocalEntry: false,
            serviceAvailable: true
        ))
        #expect(policy.shouldTranslate(
            text: "尽快推进",
            language: .chinese,
            route: .localDictionaryFirst,
            hasLocalEntry: false,
            serviceAvailable: true
        ))
    }

    @Test("Dictionary entries, unavailable services and long passages stay manual")
    func guardedCasesStayManual() {
        #expect(!policy.shouldTranslate(
            text: "prioritize",
            language: .english,
            route: .localDictionaryFirst,
            hasLocalEntry: true,
            serviceAvailable: true
        ))
        #expect(!policy.shouldTranslate(
            text: "I will follow up tomorrow.",
            language: .english,
            route: .modelRecommended,
            hasLocalEntry: false,
            serviceAvailable: false
        ))
        #expect(!policy.shouldTranslate(
            text: String(repeating: "word ", count: 80),
            language: .english,
            route: .modelRecommended,
            hasLocalEntry: false,
            serviceAvailable: true
        ))
    }

    @Test("A single unknown word still shows lookup controls instead of auto translating")
    func singleUnknownWordStaysManual() {
        #expect(!policy.shouldTranslate(
            text: "unlistedword",
            language: .english,
            route: .localDictionaryFirst,
            hasLocalEntry: false,
            serviceAvailable: true
        ))
    }
}

