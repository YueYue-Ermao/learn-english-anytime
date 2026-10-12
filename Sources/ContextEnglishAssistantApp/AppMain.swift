import AppKit
import Darwin

@main
struct ContextEnglishAssistantMain {
    @MainActor
    static func main() {
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--dictionary-self-test"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            runDictionarySelfTest(path: CommandLine.arguments[flagIndex + 1])
            return
        }

        if let flagIndex = CommandLine.arguments.firstIndex(of: "--user-data-self-test"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            runUserDataSelfTest(path: CommandLine.arguments[flagIndex + 1])
            return
        }

        if let flagIndex = CommandLine.arguments.firstIndex(of: "--user-data-migration-self-test"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            runUserDataMigrationSelfTest(path: CommandLine.arguments[flagIndex + 1])
            return
        }

        if CommandLine.arguments.contains("--learning-center-layout-self-test") {
            runLearningCenterLayoutSelfTest()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    private static func runDictionarySelfTest(path: String) {
        do {
            let dictionary = try SQLiteDictionary(databaseURL: URL(fileURLWithPath: path))
            let expectations: [(query: String, headword: String, spokenText: String?)] = [
                (query: "prioritize", headword: "prioritize", spokenText: nil),
                (query: "prioritized", headword: "prioritized", spokenText: nil),
                (query: "teeth", headword: "teeth", spokenText: nil),
                (query: "product manager", headword: "product manager", spokenText: nil),
                (query: "serendipity", headword: "serendipity", spokenText: nil),
                (query: "面试", headword: "面试", spokenText: "interview"),
                (query: "项目", headword: "项目", spokenText: "project"),
                (query: "简历", headword: "简历", spokenText: "résumé"),
                (query: "优先", headword: "优先", spokenText: "prioritize")
            ]

            for expectation in expectations {
                guard let entry = dictionary.lookup(expectation.query),
                      entry.headword.caseInsensitiveCompare(expectation.headword) == .orderedSame,
                      expectation.spokenText == nil || entry.spokenText == expectation.spokenText,
                      !entry.meanings.isEmpty else {
                    fputs("Dictionary self-test failed for \(expectation.query)\n", stderr)
                    exit(1)
                }
            }
            print("Bidirectional dictionary self-test passed (\(expectations.count) cases)")
        } catch {
            fputs("Dictionary self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runUserDataSelfTest(path: String) {
        do {
            let store = try UserDataStore(databaseURL: URL(fileURLWithPath: path))
            let draft = FavoriteDraft(
                kind: .word,
                sourceText: "prioritize",
                pronunciation: "/praɪˈɔːrətaɪz/",
                meaning: "优先处理",
                note: "self-test",
                spokenText: "prioritize",
                sourceLanguage: "en",
                minimalContextText: "We need to prioritize the roadmap."
            )
            let collection = try store.createCollection(name: "面试好句")
            let sentenceDraft = FavoriteDraft(
                kind: .sentence,
                sourceText: "I started using AI to solve real business problems.",
                pronunciation: nil,
                meaning: "我开始使用 AI 解决真实的业务问题。",
                note: "self-test",
                spokenText: "I started using AI to solve real business problems.",
                sourceLanguage: "en",
                minimalContextText: nil
            )
            guard try store.toggle(draft),
                  store.contains(draft),
                  try store.fetch(search: "prior").count == 1,
                  try store.save(sentenceDraft, collectionID: collection.id),
                  try store.fetch(
                    search: nil,
                    kinds: [.sentence],
                    collectionID: collection.id
                  ).count == 1 else {
                fputs("User data self-test failed\n", stderr)
                exit(1)
            }
            try store.deleteCollection(id: collection.id)
            let movedSentences = try store.fetch(
                search: nil,
                kinds: [.sentence],
                collectionID: defaultSentenceCollectionID
            )
            guard movedSentences.count == 1,
                  try store.collections().count == 1 else {
                fputs("User data collection self-test failed\n", stderr)
                exit(1)
            }
            try store.delete(id: movedSentences[0].id)
            guard !(try store.toggle(draft)),
                  try store.fetch(search: nil).isEmpty else {
                fputs("User data self-test failed\n", stderr)
                exit(1)
            }
            print("User data self-test passed")
        } catch {
            fputs("User data self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runUserDataMigrationSelfTest(path: String) {
        do {
            let store = try UserDataStore(databaseURL: URL(fileURLWithPath: path))
            let collections = try store.collections()
            let sentences = try store.fetch(
                search: nil,
                kinds: [.sentence, .contextualExpression],
                collectionID: defaultSentenceCollectionID
            )
            guard collections.contains(where: {
                $0.id == defaultSentenceCollectionID && $0.isSystem
            }),
            sentences.count == 1,
            sentences[0].sourceText == "An existing saved sentence." else {
                fputs("User data migration self-test failed\n", stderr)
                exit(1)
            }
            print("User data v1→v2 migration self-test passed")
        } catch {
            fputs("User data migration self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runLearningCenterLayoutSelfTest() {
        _ = NSApplication.shared
        let controller = LearningCenterWindowController(
            repository: InMemoryFavoritesRepository(),
            grammarService: GrammarLayoutSelfTestService()
        )
        for section in [LearningCenterSection.words, .sentences, .grammar] {
            controller.present(section: section)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
        }
        controller.window?.orderOut(nil)
        print("Learning center layout self-test passed")
    }
}

private struct GrammarLayoutSelfTestService: GrammarQuestionProviding {
    func ask(_ request: GrammarQuestionRequest) async throws -> GrammarQuestionResponse {
        GrammarQuestionResponse(
            requestId: request.requestId,
            answerZh: "测试回答",
            highlightedForm: "started using",
            grammarPoint: "start + doing",
            explanationZh: "布局测试",
            structure: "start + doing",
            alternatives: [],
            examples: [],
            quickRuleZh: "布局测试",
            modelLabel: "layout-self-test"
        )
    }
}
