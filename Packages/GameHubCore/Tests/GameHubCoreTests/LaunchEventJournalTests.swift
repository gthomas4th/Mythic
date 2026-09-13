import XCTest
@testable import GameHubCore

final class LaunchEventJournalTests: XCTestCase {
    func file() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root.appendingPathComponent("events.json")
    }
    func event(_ id: String = "steam:42") -> LaunchDiagnosticEvent {
        .init(correlationID: UUID(), gameID: id, outcome: .requested, profileID: "accepted-42")
    }
    func testReopenRetainsOnlyLatestEventsWithPrivatePermissions() throws {
        let url = try file()
        let events = (0..<205).map { _ in event() }
        try LaunchEventJournal.save(events, to: url)
        let restored = try LaunchEventJournal.load(from: url)
        XCTAssertEqual(restored.count, 200)
        XCTAssertEqual(restored.first?.correlationID, events[5].correlationID)
        try LaunchEventJournal.save([events[0]], to: url)
        XCTAssertEqual(try LaunchEventJournal.load(from: url).first?.correlationID, events[0].correlationID)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
    func testLocalIdentityDoesNotLeakPathsIntoExport() throws {
        let value = event("/Users/private-name/Games/title.exe")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(value), encoding: .utf8))
        XCTAssertFalse(json.contains("private-name"))
        XCTAssertFalse(json.contains("title.exe"))
        XCTAssertTrue(value.gameID.hasPrefix("game:"))
        XCTAssertEqual(event().gameID, "steam:42")
    }
    func testInvalidAndOversizedSnapshotsAreRejectedWithoutChanges() throws {
        let url = try file()
        try LaunchEventJournal.save([event()], to: url)
        for data in [Data(#"{"schemaVersion":99,"events":[]}"#.utf8), Data(repeating: 32, count: 262145)] {
            try data.write(to: url)
            XCTAssertThrowsError(try LaunchEventJournal.load(from: url))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
    func testMissingJournalIsEmptyAndUnsafeProfileIsOmitted() throws {
        XCTAssertTrue(try LaunchEventJournal.load(from: file()).isEmpty)
        let value = LaunchDiagnosticEvent(correlationID: UUID(), gameID: "steam:42", outcome: .failed, profileID: "../private")
        XCTAssertNil(value.profileID)
    }
}
