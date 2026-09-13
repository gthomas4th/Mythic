import Foundation

@MainActor enum LaunchDiagnostics {
    struct Event: Codable {
        let correlationID: UUID
        let time: Date
        let gameID: String
        let outcome: String
        let profileID: String?
    }
    private static var events: [Event] = []
    static func record(_ id: UUID, game: Game, outcome: String) {
        let profile = (game as? SteamGame)?.record.flatMap { LaunchResolver.resolve($0.launchTargets)?.profileID }
        events.append(.init(correlationID: id, time: .now, gameID: game.id, outcome: outcome, profileID: profile))
        events = Array(events.suffix(200))
    }
    static func export() throws -> Data {
        struct Report: Codable {
            let schemaVersion: Int
            let applicationVersion: String
            let osVersion: String
            let memoryGB: Double
            let logicalProcessors: Int
            let events: [Event]
            let omitted: [String]
        }
        let report = Report(schemaVersion: 1,
            applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000,
            logicalProcessors: ProcessInfo.processInfo.processorCount, events: events,
            omitted: ["Raw runtime logs", "Filesystem paths", "Folder bookmarks", "Account credentials", "Network addresses"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
