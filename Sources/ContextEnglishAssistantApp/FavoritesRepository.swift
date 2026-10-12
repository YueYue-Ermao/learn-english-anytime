import CSQLite
import Foundation

enum FavoriteKind: String, Codable, CaseIterable {
    case word
    case phrase
    case sentence
    case contextualExpression = "contextual_expression"

    var displayName: String {
        switch self {
        case .word: return "单词"
        case .phrase: return "词组"
        case .sentence: return "句子"
        case .contextualExpression: return "场景表达"
        }
    }
}

struct FavoriteDraft {
    let kind: FavoriteKind
    let sourceText: String
    let pronunciation: String?
    let meaning: String
    let note: String?
    let spokenText: String
    let sourceLanguage: String
    let minimalContextText: String?

    var normalizedText: String {
        sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct FavoriteItem: Identifiable {
    let id: String
    let kind: FavoriteKind
    let sourceText: String
    let normalizedText: String
    let pronunciation: String?
    let meaning: String
    let note: String?
    let spokenText: String
    let sourceLanguage: String
    let minimalContextText: String?
    let collectionID: String?
    let createdAt: Date
    let updatedAt: Date
}

struct FavoriteCollection: Identifiable, Equatable {
    let id: String
    let name: String
    let isSystem: Bool
    let createdAt: Date
}

let defaultSentenceCollectionID = "default-sentences"

@MainActor
protocol FavoritesRepository: AnyObject {
    func contains(_ draft: FavoriteDraft) -> Bool
    @discardableResult func toggle(_ draft: FavoriteDraft) throws -> Bool
    @discardableResult func save(_ draft: FavoriteDraft, collectionID: String?) throws -> Bool
    func fetch(search: String?) throws -> [FavoriteItem]
    func fetch(
        search: String?,
        kinds: [FavoriteKind],
        collectionID: String?
    ) throws -> [FavoriteItem]
    func delete(id: String) throws
    func collections() throws -> [FavoriteCollection]
    func createCollection(name: String) throws -> FavoriteCollection
    func deleteCollection(id: String) throws
    func moveFavorite(id: String, to collectionID: String) throws
}

enum UserDataStoreError: LocalizedError {
    case applicationSupportUnavailable
    case openFailed(String)
    case migrationFailed(String)
    case statementFailed(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法访问应用数据目录"
        case .openFailed(let message):
            return "无法打开收藏数据库：\(message)"
        case .migrationFailed(let message):
            return "无法初始化收藏数据库：\(message)"
        case .statementFailed(let message):
            return "收藏数据库操作失败：\(message)"
        }
    }
}

@MainActor
final class UserDataStore: FavoritesRepository {
    private var database: OpaquePointer?

    static func openDefault() throws -> UserDataStore {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw UserDataStoreError.applicationSupportUnavailable
        }

        let directory = applicationSupport.appendingPathComponent(
            "Context English Assistant",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return try UserDataStore(databaseURL: directory.appendingPathComponent("user.sqlite3"))
    }

    init(databaseURL: URL) throws {
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            let message = errorMessage
            if let database { sqlite3_close(database) }
            database = nil
            throw UserDataStoreError.openFailed(message)
        }

        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try migrate()
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func contains(_ draft: FavoriteDraft) -> Bool {
        guard let database else { return false }
        let sql = "SELECT 1 FROM favorites WHERE kind = ? AND normalized_text = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        guard bind(draft.kind.rawValue, to: statement, index: 1) == SQLITE_OK,
              bind(draft.normalizedText, to: statement, index: 2) == SQLITE_OK else {
            return false
        }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    @discardableResult
    func toggle(_ draft: FavoriteDraft) throws -> Bool {
        if contains(draft) {
            try delete(kind: draft.kind, normalizedText: draft.normalizedText)
            return false
        }

        let collectionID = sentenceCollectionID(for: draft, requested: nil)
        try insert(draft, collectionID: collectionID)
        return true
    }

    @discardableResult
    func save(_ draft: FavoriteDraft, collectionID: String?) throws -> Bool {
        let resolvedCollectionID = sentenceCollectionID(for: draft, requested: collectionID)
        if let existingID = favoriteID(kind: draft.kind, normalizedText: draft.normalizedText) {
            if let resolvedCollectionID {
                try moveFavorite(id: existingID, to: resolvedCollectionID)
            }
            return false
        }
        try insert(draft, collectionID: resolvedCollectionID)
        return true
    }

    private func insert(_ draft: FavoriteDraft, collectionID: String?) throws {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        let sql = """
        INSERT INTO favorites (
            id, kind, source_text, normalized_text, pronunciation, meaning,
            note, spoken_text, source_language, minimal_context_text,
            collection_id, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        let now = Date().timeIntervalSince1970
        let values: [String?] = [
            UUID().uuidString,
            draft.kind.rawValue,
            draft.sourceText,
            draft.normalizedText,
            draft.pronunciation,
            draft.meaning,
            draft.note,
            draft.spokenText,
            draft.sourceLanguage,
            draft.minimalContextText,
            collectionID
        ]
        for (offset, value) in values.enumerated() {
            guard bind(value, to: statement, index: Int32(offset + 1)) == SQLITE_OK else {
                throw UserDataStoreError.statementFailed(errorMessage)
            }
        }
        sqlite3_bind_double(statement, 12, now)
        sqlite3_bind_double(statement, 13, now)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
    }

    func fetch(search: String? = nil) throws -> [FavoriteItem] {
        try fetch(search: search, kinds: [], collectionID: nil)
    }

    func fetch(
        search: String?,
        kinds: [FavoriteKind],
        collectionID: String?
    ) throws -> [FavoriteItem] {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }

        let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSearch = !trimmedSearch.isEmpty
        var conditions: [String] = []
        var values: [String] = []
        if hasSearch {
            conditions.append("(source_text LIKE ? OR meaning LIKE ?)")
            let pattern = "%\(trimmedSearch)%"
            values.append(contentsOf: [pattern, pattern])
        }
        if !kinds.isEmpty {
            conditions.append("kind IN (\(Array(repeating: "?", count: kinds.count).joined(separator: ",")))")
            values.append(contentsOf: kinds.map(\.rawValue))
        }
        if let collectionID {
            conditions.append("collection_id = ?")
            values.append(collectionID)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let sql = """
        SELECT id, kind, source_text, normalized_text, pronunciation, meaning,
               note, spoken_text, source_language, minimal_context_text,
               collection_id, created_at, updated_at
        FROM favorites
        \(whereClause)
        ORDER BY updated_at DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in values.enumerated() {
            guard bind(value, to: statement, index: Int32(offset + 1)) == SQLITE_OK else {
                throw UserDataStoreError.statementFailed(errorMessage)
            }
        }

        var items: [FavoriteItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = columnText(statement, index: 0),
                  let kindValue = columnText(statement, index: 1),
                  let kind = FavoriteKind(rawValue: kindValue),
                  let sourceText = columnText(statement, index: 2),
                  let normalizedText = columnText(statement, index: 3),
                  let meaning = columnText(statement, index: 5),
                  let spokenText = columnText(statement, index: 7),
                  let sourceLanguage = columnText(statement, index: 8) else {
                continue
            }
            items.append(FavoriteItem(
                id: id,
                kind: kind,
                sourceText: sourceText,
                normalizedText: normalizedText,
                pronunciation: columnText(statement, index: 4),
                meaning: meaning,
                note: columnText(statement, index: 6),
                spokenText: spokenText,
                sourceLanguage: sourceLanguage,
                minimalContextText: columnText(statement, index: 9),
                collectionID: columnText(statement, index: 10),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12))
            ))
        }
        return items
    }

    func delete(id: String) throws {
        try runDelete(sql: "DELETE FROM favorites WHERE id = ?", values: [id])
    }

    func collections() throws -> [FavoriteCollection] {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        let sql = """
        SELECT id, name, is_system, created_at
        FROM favorite_collections
        ORDER BY is_system DESC, created_at ASC, name COLLATE NOCASE ASC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }

        var result: [FavoriteCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = columnText(statement, index: 0),
                  let name = columnText(statement, index: 1) else { continue }
            result.append(FavoriteCollection(
                id: id,
                name: name,
                isSystem: sqlite3_column_int(statement, 2) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        return result
    }

    func createCollection(name: String) throws -> FavoriteCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UserDataStoreError.statementFailed("收藏夹名称不能为空")
        }
        guard trimmed.count <= 40 else {
            throw UserDataStoreError.statementFailed("收藏夹名称不能超过 40 个字符")
        }
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        let item = FavoriteCollection(
            id: UUID().uuidString,
            name: trimmed,
            isSystem: false,
            createdAt: Date()
        )
        let sql = "INSERT INTO favorite_collections (id, name, is_system, created_at) VALUES (?, ?, 0, ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard bind(item.id, to: statement, index: 1) == SQLITE_OK,
              bind(item.name, to: statement, index: 2) == SQLITE_OK else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        sqlite3_bind_double(statement, 3, item.createdAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            let message = sqlite3_errcode(database) == SQLITE_CONSTRAINT
                ? "已存在同名收藏夹"
                : errorMessage
            throw UserDataStoreError.statementFailed(message)
        }
        return item
    }

    func deleteCollection(id: String) throws {
        guard id != defaultSentenceCollectionID else {
            throw UserDataStoreError.statementFailed("默认好句收藏夹不能删除")
        }
        do {
            try execute("BEGIN IMMEDIATE;")
            try updateFavoriteCollection(from: id, to: defaultSentenceCollectionID)
            try runDelete(sql: "DELETE FROM favorite_collections WHERE id = ?", values: [id])
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func moveFavorite(id: String, to collectionID: String) throws {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        let sql = "UPDATE favorites SET collection_id = ?, updated_at = ? WHERE id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard bind(collectionID, to: statement, index: 1) == SQLITE_OK,
              bind(id, to: statement, index: 3) == SQLITE_OK else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
    }

    private func delete(kind: FavoriteKind, normalizedText: String) throws {
        try runDelete(
            sql: "DELETE FROM favorites WHERE kind = ? AND normalized_text = ?",
            values: [kind.rawValue, normalizedText]
        )
    }

    private func sentenceCollectionID(for draft: FavoriteDraft, requested: String?) -> String? {
        switch draft.kind {
        case .sentence, .contextualExpression:
            return requested ?? defaultSentenceCollectionID
        case .word, .phrase:
            return nil
        }
    }

    private func favoriteID(kind: FavoriteKind, normalizedText: String) -> String? {
        guard let database else { return nil }
        let sql = "SELECT id FROM favorites WHERE kind = ? AND normalized_text = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard bind(kind.rawValue, to: statement, index: 1) == SQLITE_OK,
              bind(normalizedText, to: statement, index: 2) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return columnText(statement, index: 0)
    }

    private func updateFavoriteCollection(from sourceID: String, to targetID: String) throws {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        let sql = "UPDATE favorites SET collection_id = ?, updated_at = ? WHERE collection_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard bind(targetID, to: statement, index: 1) == SQLITE_OK,
              bind(sourceID, to: statement, index: 3) == SQLITE_OK else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
    }

    private func runDelete(sql: String, values: [String]) throws {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            guard bind(value, to: statement, index: Int32(offset + 1)) == SQLITE_OK else {
                throw UserDataStoreError.statementFailed(errorMessage)
            }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UserDataStoreError.statementFailed(errorMessage)
        }
    }

    private func migrate() throws {
        let baseSchema = """
        CREATE TABLE IF NOT EXISTS favorite_collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            is_system INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS favorites (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            source_text TEXT NOT NULL,
            normalized_text TEXT NOT NULL,
            pronunciation TEXT,
            meaning TEXT NOT NULL,
            note TEXT,
            spoken_text TEXT NOT NULL,
            source_language TEXT NOT NULL,
            minimal_context_text TEXT,
            collection_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(kind, normalized_text)
        );
        CREATE INDEX IF NOT EXISTS idx_favorites_updated_at
            ON favorites(updated_at DESC);
        """
        do {
            try execute(baseSchema)
            if !columnExists(table: "favorites", column: "collection_id") {
                try execute("ALTER TABLE favorites ADD COLUMN collection_id TEXT;")
            }
            let now = Date().timeIntervalSince1970
            try execute("""
            INSERT OR IGNORE INTO favorite_collections (id, name, is_system, created_at)
            VALUES ('\(defaultSentenceCollectionID)', '默认好句', 1, \(now));
            UPDATE favorites
            SET collection_id = '\(defaultSentenceCollectionID)'
            WHERE collection_id IS NULL
              AND kind IN ('sentence', 'contextual_expression');
            CREATE INDEX IF NOT EXISTS idx_favorites_collection_id
                ON favorites(collection_id, updated_at DESC);
            PRAGMA user_version = 2;
            """)
        } catch {
            throw UserDataStoreError.migrationFailed(error.localizedDescription)
        }
    }

    private func columnExists(table: String, column: String) -> Bool {
        guard let database else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, index: 1) == column { return true }
        }
        return false
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw UserDataStoreError.statementFailed("数据库未打开")
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(errorPointer)
            throw UserDataStoreError.statementFailed(message)
        }
    }

    private func bind(_ value: String?, to statement: OpaquePointer, index: Int32) -> Int32 {
        guard let value else { return sqlite3_bind_null(statement, index) }
        return value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, SQLITE_USER_DATA_TRANSIENT)
        }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private var errorMessage: String {
        database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "unknown SQLite error"
    }
}

@MainActor
final class InMemoryFavoritesRepository: FavoritesRepository {
    private var items: [FavoriteItem] = []
    private var collectionItems: [FavoriteCollection] = [FavoriteCollection(
        id: defaultSentenceCollectionID,
        name: "默认好句",
        isSystem: true,
        createdAt: Date()
    )]

    func contains(_ draft: FavoriteDraft) -> Bool {
        items.contains { $0.kind == draft.kind && $0.normalizedText == draft.normalizedText }
    }

    func toggle(_ draft: FavoriteDraft) throws -> Bool {
        if let index = items.firstIndex(where: {
            $0.kind == draft.kind && $0.normalizedText == draft.normalizedText
        }) {
            items.remove(at: index)
            return false
        }
        let now = Date()
        let collectionID: String? = [.sentence, .contextualExpression].contains(draft.kind)
            ? defaultSentenceCollectionID
            : nil
        items.insert(FavoriteItem(
            id: UUID().uuidString,
            kind: draft.kind,
            sourceText: draft.sourceText,
            normalizedText: draft.normalizedText,
            pronunciation: draft.pronunciation,
            meaning: draft.meaning,
            note: draft.note,
            spokenText: draft.spokenText,
            sourceLanguage: draft.sourceLanguage,
            minimalContextText: draft.minimalContextText,
            collectionID: collectionID,
            createdAt: now,
            updatedAt: now
        ), at: 0)
        return true
    }

    func save(_ draft: FavoriteDraft, collectionID: String?) throws -> Bool {
        if let index = items.firstIndex(where: {
            $0.kind == draft.kind && $0.normalizedText == draft.normalizedText
        }) {
            if let collectionID {
                let item = items[index]
                items[index] = FavoriteItem(
                    id: item.id,
                    kind: item.kind,
                    sourceText: item.sourceText,
                    normalizedText: item.normalizedText,
                    pronunciation: item.pronunciation,
                    meaning: item.meaning,
                    note: item.note,
                    spokenText: item.spokenText,
                    sourceLanguage: item.sourceLanguage,
                    minimalContextText: item.minimalContextText,
                    collectionID: collectionID,
                    createdAt: item.createdAt,
                    updatedAt: Date()
                )
            }
            return false
        }
        let now = Date()
        items.insert(FavoriteItem(
            id: UUID().uuidString,
            kind: draft.kind,
            sourceText: draft.sourceText,
            normalizedText: draft.normalizedText,
            pronunciation: draft.pronunciation,
            meaning: draft.meaning,
            note: draft.note,
            spokenText: draft.spokenText,
            sourceLanguage: draft.sourceLanguage,
            minimalContextText: draft.minimalContextText,
            collectionID: [.sentence, .contextualExpression].contains(draft.kind)
                ? (collectionID ?? defaultSentenceCollectionID)
                : nil,
            createdAt: now,
            updatedAt: now
        ), at: 0)
        return true
    }

    func fetch(search: String?) throws -> [FavoriteItem] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.sourceText.localizedCaseInsensitiveContains(query)
                || $0.meaning.localizedCaseInsensitiveContains(query)
        }
    }

    func fetch(
        search: String?,
        kinds: [FavoriteKind],
        collectionID: String?
    ) throws -> [FavoriteItem] {
        let query = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return items.filter { item in
            (kinds.isEmpty || kinds.contains(item.kind))
                && (collectionID == nil || item.collectionID == collectionID)
                && (query.isEmpty
                    || item.sourceText.localizedCaseInsensitiveContains(query)
                    || item.meaning.localizedCaseInsensitiveContains(query))
        }
    }

    func delete(id: String) throws {
        items.removeAll { $0.id == id }
    }

    func collections() throws -> [FavoriteCollection] {
        collectionItems
    }

    func createCollection(name: String) throws -> FavoriteCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UserDataStoreError.statementFailed("收藏夹名称不能为空")
        }
        guard !collectionItems.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw UserDataStoreError.statementFailed("已存在同名收藏夹")
        }
        let value = FavoriteCollection(id: UUID().uuidString, name: trimmed, isSystem: false, createdAt: Date())
        collectionItems.append(value)
        return value
    }

    func deleteCollection(id: String) throws {
        guard id != defaultSentenceCollectionID else {
            throw UserDataStoreError.statementFailed("默认好句收藏夹不能删除")
        }
        collectionItems.removeAll { $0.id == id }
        for index in items.indices where items[index].collectionID == id {
            let item = items[index]
            items[index] = FavoriteItem(
                id: item.id,
                kind: item.kind,
                sourceText: item.sourceText,
                normalizedText: item.normalizedText,
                pronunciation: item.pronunciation,
                meaning: item.meaning,
                note: item.note,
                spokenText: item.spokenText,
                sourceLanguage: item.sourceLanguage,
                minimalContextText: item.minimalContextText,
                collectionID: defaultSentenceCollectionID,
                createdAt: item.createdAt,
                updatedAt: Date()
            )
        }
    }

    func moveFavorite(id: String, to collectionID: String) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]
        items[index] = FavoriteItem(
            id: item.id,
            kind: item.kind,
            sourceText: item.sourceText,
            normalizedText: item.normalizedText,
            pronunciation: item.pronunciation,
            meaning: item.meaning,
            note: item.note,
            spokenText: item.spokenText,
            sourceLanguage: item.sourceLanguage,
            minimalContextText: item.minimalContextText,
            collectionID: collectionID,
            createdAt: item.createdAt,
            updatedAt: Date()
        )
    }
}

private let SQLITE_USER_DATA_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
