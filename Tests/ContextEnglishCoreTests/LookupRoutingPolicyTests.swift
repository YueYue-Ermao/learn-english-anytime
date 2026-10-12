import Testing
@testable import ContextEnglishCore

@Suite("Lookup routing policy")
struct LookupRoutingPolicyTests {
    private let policy = LookupRoutingPolicy()

    @Test("Simple English and Chinese terms prefer the offline dictionary")
    func lexicalSelectionsPreferDictionary() {
        #expect(policy.route(for: "prioritize", language: .english) == .localDictionaryFirst)
        #expect(policy.route(for: "product manager", language: .english) == .localDictionaryFirst)
        #expect(policy.route(for: "面试", language: .chinese) == .localDictionaryFirst)
        #expect(policy.route(for: "优先处理", language: .chinese) == .localDictionaryFirst)
    }

    @Test("Sentences and mixed expressions recommend the model")
    func expressionsRecommendModel() {
        #expect(policy.route(
            for: "我会先确认需求优先级，再和研发评估实现成本。",
            language: .chinese
        ) == .modelRecommended)
        #expect(policy.route(
            for: "I would first clarify the priorities with the team.",
            language: .english
        ) == .modelRecommended)
        #expect(policy.route(for: "推进 roadmap", language: .mixed) == .modelRecommended)
    }
}
