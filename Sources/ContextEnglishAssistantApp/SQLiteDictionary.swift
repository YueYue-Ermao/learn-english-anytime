import CSQLite
import ContextEnglishCore
import Foundation

final class SQLiteDictionary: DictionaryProviding {
    enum DictionaryError: Error {
        case databaseResourceMissing
        case databaseOpenFailed(String)
    }

    private final class CacheValue {
        let entry: DictionaryEntry?

        init(_ entry: DictionaryEntry?) {
            self.entry = entry
        }
    }

    private var database: OpaquePointer?
    private let cache = NSCache<NSString, CacheValue>()

    static func bundled() throws -> SQLiteDictionary {
        guard let url = Bundle.main.url(forResource: "ecdict", withExtension: "sqlite3") else {
            throw DictionaryError.databaseResourceMissing
        }
        return try SQLiteDictionary(databaseURL: url)
    }

    init(databaseURL: URL) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &database, flags, nil)
        guard result == SQLITE_OK else {
            let message = database.flatMap(sqlite3_errmsg).map(String.init(cString:))
                ?? "unknown SQLite error"
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw DictionaryError.databaseOpenFailed(message)
        }
        cache.countLimit = 1_000
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func lookup(_ text: String) -> DictionaryEntry? {
        let query = text.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        guard !query.isEmpty, query.count <= 120 else { return nil }

        let cacheKey = query.lowercased() as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached.entry
        }

        let result: DictionaryEntry?
        if TextLanguageDetector.detect(query) == .chinese {
            result = chineseEntry(for: query)
        } else {
            result = exactEntry(for: query)
                ?? lemmaEntry(for: query)
                ?? normalizedEntry(for: query)
        }
        cache.setObject(CacheValue(result), forKey: cacheKey)
        return result
    }

    private func chineseEntry(for query: String) -> DictionaryEntry? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        let sql = """
        SELECT z.word, e.phonetic, e.pos
        FROM zh_lookup z
        LEFT JOIN entries e ON e.word = z.word COLLATE NOCASE
        WHERE z.term = ?
        ORDER BY z.rank DESC, length(z.word) ASC
        LIMIT 5
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let bindResult = query.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, SQLITE_TRANSIENT)
        }
        guard bindResult == SQLITE_OK else { return nil }

        var candidates: [(word: String, phonetic: String?, partOfSpeech: String?)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let word = columnText(statement, index: 0) else { continue }
            candidates.append((
                word: word,
                phonetic: cleanPhonetic(columnText(statement, index: 1)),
                partOfSpeech: formattedPartOfSpeech(columnText(statement, index: 2))
            ))
        }
        guard let primary = candidates.first else { return nil }

        let meanings = candidates.map { candidate in
            guard let partOfSpeech = candidate.partOfSpeech else { return candidate.word }
            return "\(candidate.word)（\(partOfSpeech)）"
        }
        return DictionaryEntry(
            headword: query,
            phonetic: primary.phonetic,
            partOfSpeech: "汉英",
            meanings: meanings,
            usageNote: "ECDICT 汉英离线反查 · 可按需使用模型结合所在句确定最自然的表达。",
            spokenText: primary.word
        )
    }

    private func exactEntry(for query: String) -> DictionaryEntry? {
        entry(
            sql: """
            SELECT word, phonetic, definition, translation, pos
            FROM entries WHERE word = ? COLLATE NOCASE LIMIT 1
            """,
            parameter: query,
            originalQuery: query,
            matchedViaLemma: false
        )
    }

    private func lemmaEntry(for query: String) -> DictionaryEntry? {
        entry(
            sql: """
            SELECT e.word, e.phonetic, e.definition, e.translation, e.pos
            FROM forms f JOIN entries e ON e.word = f.lemma COLLATE NOCASE
            WHERE f.form = ? COLLATE NOCASE LIMIT 1
            """,
            parameter: query,
            originalQuery: query,
            matchedViaLemma: true
        )
    }

    private func normalizedEntry(for query: String) -> DictionaryEntry? {
        let normalized = query.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        guard !normalized.isEmpty else { return nil }

        return entry(
            sql: """
            SELECT word, phonetic, definition, translation, pos
            FROM entries WHERE normalized = ?
            ORDER BY frequency DESC, bnc ASC LIMIT 1
            """,
            parameter: normalized,
            originalQuery: query,
            matchedViaLemma: false
        )
    }

    private func entry(
        sql: String,
        parameter: String,
        originalQuery: String,
        matchedViaLemma: Bool
    ) -> DictionaryEntry? {
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let bindResult = parameter.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, SQLITE_TRANSIENT)
        }
        guard bindResult == SQLITE_OK else { return nil }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let word = columnText(statement, index: 0) ?? originalQuery
        let phoneticValue = columnText(statement, index: 1)
        let definition = columnText(statement, index: 2)
        let translation = columnText(statement, index: 3)
        let partOfSpeech = formattedPartOfSpeech(columnText(statement, index: 4))
        let meanings = formattedMeanings(translation: translation, definition: definition)
        guard !meanings.isEmpty else { return nil }

        let phonetic = cleanPhonetic(phoneticValue)
        let sourceNote: String
        if matchedViaLemma, word.caseInsensitiveCompare(originalQuery) != .orderedSame {
            sourceNote = "词形还原：\(originalQuery) → \(word) · ECDICT 离线词典"
        } else {
            sourceNote = "ECDICT 离线词典"
        }

        return DictionaryEntry(
            headword: word,
            phonetic: phonetic,
            partOfSpeech: partOfSpeech,
            meanings: meanings,
            usageNote: sourceNote
        )
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func formattedMeanings(translation: String?, definition: String?) -> [String] {
        let chineseMeanings = splitLines(translation)
        if !chineseMeanings.isEmpty {
            return Array(chineseMeanings.prefix(4))
        }

        let englishMeanings = splitLines(definition)
        guard !englishMeanings.isEmpty else { return [] }
        return Array(englishMeanings.prefix(5)).map { "英英：\($0)" }
    }

    private func splitLines(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value.replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func cleanPhonetic(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)/"
    }

    private func formattedPartOfSpeech(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.split(separator: "/").compactMap { component -> String? in
            guard let code = component.split(separator: ":").first, !code.isEmpty else {
                return nil
            }
            return "\(code)."
        }
        guard !parts.isEmpty else { return nil }
        return parts.prefix(3).joined(separator: "/")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
