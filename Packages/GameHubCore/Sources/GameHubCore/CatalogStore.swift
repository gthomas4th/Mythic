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
            guard version <= 2 else { throw StoreError.newerSchema }
            if version == 1 {
                let backupURL = url.appendingPathExtension("schema1-backup")
                if !FileManager.default.fileExists(atPath: backupURL.path) {
                    let staging = url.appendingPathExtension("backup-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: staging) }
                    var backupDB: OpaquePointer?
                    guard sqlite3_open(staging.path, &backupDB) == SQLITE_OK else { sqlite3_close(backupDB); throw StoreError.database }
                    defer { sqlite3_close(backupDB) }
                    guard let backup = sqlite3_backup_init(backupDB, "main", database, "main") else { throw StoreError.database }
                    let result = sqlite3_backup_step(backup, -1)
                    let finished = sqlite3_backup_finish(backup)
                    guard result == SQLITE_DONE, finished == SQLITE_OK else { throw StoreError.database }
                    try FileManager.default.moveItem(at: staging, to: backupURL)
                }
            }
            try execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS preferences (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS game_details (id TEXT PRIMARY KEY, payload TEXT NOT NULL)")
            try execute("CREATE TABLE IF NOT EXISTS migrations (id TEXT PRIMARY KEY)")
            try execute("PRAGMA user_version=2")
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
    /// An empty imported catalog is distinct from an import that has never run.
    public func importedGameDetails() throws -> [String: Data]? {
        guard !(try query("SELECT id FROM migrations WHERE id='legacy-defaults-v1'")).isEmpty else { return nil }
        var result: [String: Data] = [:]
        for json in try query("SELECT payload FROM game_details ORDER BY id") {
            let row = try JSONDecoder().decode(Detail.self, from: Data(json.utf8))
            guard result[row.id] == nil else { throw StoreError.invalidData }
            result[row.id] = row.data
        }
        return result
    }
    private struct Detail: Codable { let id: String; let data: Data }
    @discardableResult public func importGameDetailsOnce(_ details: [String: Data]) throws -> Bool {
        guard try importedGameDetails() == nil else { return false }
        try replaceGameDetails(details)
        return true
    }
    /// Metadata-only snapshot transaction. No game file, save or defaults key is changed.
    public func replaceGameDetails(_ details: [String: Data]) throws {
        guard details.count <= 100000, details.values.allSatisfy({ $0.count <= 8 * 1024 * 1024 }) else { throw StoreError.invalidData }
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM game_details")
            for (id, data) in details {
                guard let json = String(data: try JSONEncoder().encode(Detail(id: id, data: data)), encoding: .utf8) else { throw StoreError.invalidData }
                try execute("INSERT INTO game_details VALUES (?, ?)", [id, json])
            }
            try execute("INSERT OR IGNORE INTO migrations VALUES ('legacy-defaults-v1')")
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
