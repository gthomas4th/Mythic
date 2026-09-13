import Foundation
import SQLite3

/// Versioned SQLite catalog; legacy defaults remain untouched as a recovery source.
public final class CatalogStore {
    private var database: OpaquePointer?
    public struct Preference: Codable, Sendable {
        public var favorite: Bool = false
        public var lastPlayed: Date?
        public var preferredTargetID: String?
        public init(favorite: Bool = false, lastPlayed: Date? = nil, preferredTargetID: String? = nil) {
            self.favorite = favorite; self.lastPlayed = lastPlayed; self.preferredTargetID = preferredTargetID
        }
    }
    public enum StoreError: Error { case database, newerSchema, invalidData }
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { sqlite3_close(database); throw StoreError.database }
        do {
            let version = try query("PRAGMA user_version").first.flatMap(Int.init) ?? 0
            guard version <= 1 else { throw StoreError.newerSchema }
            try execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS preferences (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("PRAGMA user_version=1")
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }
    private func execute(_ sql: String, _ values: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.database }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw StoreError.database }
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw StoreError.database }
    }
    private func query(_ sql: String, _ values: [String] = []) throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreError.database }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var result: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else { throw StoreError.database }
            result.append(String(cString: value))
        }
    }
    public func upsert(_ records: [GameRecord]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for record in LaunchResolver.merge(records) {
                guard let json = String(data: try JSONEncoder().encode(record), encoding: .utf8) else { throw StoreError.invalidData }
                try execute("INSERT OR REPLACE INTO records VALUES (?, ?)", [record.id.description, json])
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func records() throws -> [GameRecord] {
        try query("SELECT payload FROM records ORDER BY id").map { try JSONDecoder().decode(GameRecord.self, from: Data($0.utf8)) }
    }
    public func preference(for id: String) throws -> Preference {
        guard let json = try query("SELECT payload FROM preferences WHERE id=?", [id]).first else { return .init() }
        return try JSONDecoder().decode(Preference.self, from: Data(json.utf8))
    }
    public func setPreference(_ preference: Preference, for id: String) throws {
        guard let json = String(data: try JSONEncoder().encode(preference), encoding: .utf8) else { throw StoreError.invalidData }
        try execute("INSERT OR REPLACE INTO preferences VALUES (?, ?)", [id, json])
    }
}
