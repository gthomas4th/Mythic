import Foundation

@MainActor enum LaunchDiagnostics {
    private static let file = GameHubRuntime.support.appendingPathComponent("Diagnostics/launch-events.json")
    private static var persistenceUnavailable = false
    private static var events: [LaunchDiagnosticEvent] = {
        do { return try LaunchEventJournal.load(from: file) } catch { persistenceUnavailable = true; return [] }
    }()
    static func record(_ id: UUID, game: Game, outcome: String) {
        guard let outcome = LaunchDiagnosticEvent.Outcome(rawValue: outcome) else { return }
        let steam = game as? SteamGame
        let profile = steam?.record.flatMap { record in
            let target = record.launchTargets.first { $0.id == steam?.preferredTargetID && $0.kind == .moonlight }
                ?? LaunchResolver.resolve(record.launchTargets, preferredID: steam?.preferredTargetID)
            return target?.profileID
        }
        events.append(.init(correlationID: id, gameID: game.id, outcome: outcome, profileID: profile))
        events = Array(events.suffix(LaunchEventJournal.limit))
        // Preserve an unreadable or newer snapshot instead of overwriting recovery evidence.
        guard !persistenceUnavailable else { return }
        do { try LaunchEventJournal.save(events, to: file) } catch { persistenceUnavailable = true }
    }
    static func export() throws -> Data {
        struct Report: Codable {
            let schemaVersion: Int
            let applicationVersion: String
            let osVersion: String
            let memoryGB: Double
            let logicalProcessors: Int
            let events: [LaunchDiagnosticEvent]
            let persistenceUnavailable: Bool
            let omitted: [String]
        }
        let report = Report(schemaVersion: 1,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000,
            logicalProcessors: ProcessInfo.processInfo.processorCount, events: events,
            persistenceUnavailable: persistenceUnavailable,
            omitted: ["Raw runtime logs", "Filesystem paths", "Folder bookmarks", "Account credentials", "Network addresses"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
