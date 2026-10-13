import Foundation

public struct DictionaryEntry: Equatable, Sendable {
    public let headword: String
    public let phonetic: String?
    public let partOfSpeech: String?
    public let meanings: [String]
    public let synonyms: [String]
    public let usageNote: String?
    public let spokenText: String?

    public init(
        headword: String,
        phonetic: String?,
        partOfSpeech: String?,
        meanings: [String],
        synonyms: [String] = [],
        usageNote: String?,
        spokenText: String? = nil
    ) {
        self.headword = headword
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.meanings = meanings
        self.synonyms = synonyms
        self.usageNote = usageNote
        self.spokenText = spokenText
    }
}

public protocol DictionaryProviding {
    func lookup(_ text: String) -> DictionaryEntry?
}

public struct PrototypeDictionary: DictionaryProviding, Sendable {
    private let entries: [String: DictionaryEntry]

    public init() {
        entries = [
            "prioritize": DictionaryEntry(
                headword: "prioritize",
                phonetic: "/praɪˈɔːrətaɪz/",
                partOfSpeech: "verb",
                meanings: ["确定优先顺序", "优先处理"],
                synonyms: ["rank", "order"],
                usageNote: "产品和项目管理中常用于说明如何安排需求或任务。"
            ),
            "align": DictionaryEntry(
                headword: "align",
                phonetic: "/əˈlaɪn/",
                partOfSpeech: "verb",
                meanings: ["使一致", "就目标或优先级达成一致"],
                synonyms: ["coordinate", "adjust"],
                usageNote: "职场中常见搭配：align on priorities。"
            ),
            "trade-off": DictionaryEntry(
                headword: "trade-off",
                phonetic: "/ˈtreɪd ɒf/",
                partOfSpeech: "noun",
                meanings: ["权衡", "取舍"],
                synonyms: ["compromise", "exchange"],
                usageNote: "产品决策中用于描述两个目标无法同时最大化时的选择。"
            )
        ]
    }

    public func lookup(_ text: String) -> DictionaryEntry? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        return entries[normalized]
    }
}
