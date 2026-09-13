import Foundation
import CryptoKit

public struct LaunchDiagnosticEvent: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case requested
        case handedToLauncher = "handed-to-launcher"
        case failed = "failed-preflight-or-launch"
    }
    public let correlationID: UUID
    public let time: Date
    public let gameID: String
    public let outcome: Outcome
    public let profileID: String?
    public init(correlationID: UUID, time: Date = .now, gameID: String, outcome: Outcome, profileID: String?) {
        self.correlationID = correlationID
        self.time = time
        if gameID.hasPrefix("steam:"), SteamLaunch.url(appID: String(gameID.dropFirst(6))) != nil {
            self.gameID = gameID
        } else {
            self.gameID = "game:" + SHA256.hash(data: Data(gameID.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        self.outcome = outcome
        self.profileID = profileID.flatMap { CompatibilityProfile.safeID($0) && $0.count <= 128 ? $0 : nil }
    }
    fileprivate var valid: Bool {
        let validID = (gameID.hasPrefix("steam:") && SteamLaunch.url(appID: String(gameID.dropFirst(6))) != nil)
            || (gameID.hasPrefix("game:") && gameID.count == 69 && gameID.dropFirst(5).allSatisfy { "0123456789abcdef".contains($0) })
        return validID && time.timeIntervalSince1970.isFinite
            && (profileID.map { CompatibilityProfile.safeID($0) && $0.count <= 128 } ?? true)
    }
}

/// Private, bounded launch metadata only. Raw process output is never stored here.
public enum LaunchEventJournal {
    public static let limit = 200
    private static let byteLimit = 256 * 1024
    private struct Snapshot: Codable {
        let schemaVersion: Int
        let events: [LaunchDiagnosticEvent]
    }
    public enum JournalError: Error { case invalidSnapshot }
    public static func load(from url: URL) throws -> [LaunchDiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        guard data.count <= byteLimit else { throw JournalError.invalidSnapshot }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.schemaVersion == 1, snapshot.events.count <= limit,
              snapshot.events.allSatisfy(\.valid) else { throw JournalError.invalidSnapshot }
        return snapshot.events
    }
    public static func save(_ events: [LaunchDiagnosticEvent], to url: URL) throws {
        let retained = Array(events.suffix(limit))
        guard retained.allSatisfy(\.valid) else { throw JournalError.invalidSnapshot }
        let data = try JSONEncoder().encode(Snapshot(schemaVersion: 1, events: retained))
        guard data.count <= byteLimit else { throw JournalError.invalidSnapshot }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let staging = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.createFile(atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw JournalError.invalidSnapshot
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: url)
        }
    }
}
