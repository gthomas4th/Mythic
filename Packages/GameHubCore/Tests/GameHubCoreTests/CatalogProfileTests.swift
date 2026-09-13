import XCTest
import SQLite3
@testable import GameHubCore

final class CatalogProfileTests: XCTestCase {
    func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func profile() -> CompatibilityProfile {
        .init(profileID: "steam-42", gameID: "steam:42", runtimeID: "wine-test", runtimeVersion: "10", rendererVersion: "3",
              environment: ["WINEMSYNC": "0"], arguments: ["-windowed", "-ResX=1920"], validation: "owner-accepted", notes: "Synthetic")
    }
    func target(_ id: String, _ kind: LaunchTarget.Kind, available: Bool = true, verified: Bool = false) -> LaunchTarget {
        .init(id: id, kind: kind, locator: URL(string: "steam://rungameid/42")!, application: URL(fileURLWithPath: "/synthetic"), available: available, verified: verified)
    }
    func testResolverPreferenceAndUnavailableFallback() {
        let native = target("native", .nativeMac)
        let remote = target("remote", .moonlight)
        XCTAssertEqual(LaunchResolver.resolve([remote, native])?.id, "native")
        XCTAssertEqual(LaunchResolver.resolve([remote, native], preferredID: "remote")?.id, "remote")
        XCTAssertEqual(LaunchResolver.resolve([target("remote", .moonlight, available: false), native], preferredID: "remote")?.id, "native")
        XCTAssertNil(LaunchResolver.resolve([target("missing", .wineSteam, available: false)]))
    }
    func testVerifiedWinePrecedesRemote() {
        XCTAssertEqual(LaunchResolver.resolve([target("remote", .moonlight), target("wine", .wineSteam, verified: true)])?.id, "wine")
        XCTAssertEqual(LaunchResolver.resolve([target("remote", .moonlight), target("wine", .wineSteam)])?.id, "remote")
    }
    func testMergePreservesStoreIdentitiesAndTargets() {
        let native = GameRecord(id: .init(provider: .steam, externalID: "42"), title: "Same", launchTargets: [target("native", .nativeMac)], artwork: nil)
        let wine = GameRecord(id: native.id, title: "Same", launchTargets: [target("wine", .wineSteam)], artwork: nil)
        let epic = GameRecord(id: .init(provider: .epic, externalID: "42"), title: "Same", launchTargets: [], artwork: nil)
        let result = LaunchResolver.merge([native, wine, epic, native])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.id == native.id })?.launchTargets.count, 2)
    }
    func testCatalogSurvivesReopenAndQuotedIdentity() throws {
        let file = try folder().appendingPathComponent("catalog.sqlite")
        let record = GameRecord(id: .init(provider: .local, externalID: "O'Brien"), title: "Quoted", launchTargets: [], artwork: nil)
        do {
            let store = try CatalogStore(url: file)
            try store.upsert([record])
            try store.setPreference(.init(favorite: true, preferredTargetID: "remote"), for: record.id.description)
        }
        let reopened = try CatalogStore(url: file)
        XCTAssertEqual(try reopened.records().first?.id, record.id)
        XCTAssertTrue(try reopened.preference(for: record.id.description).favorite)
        XCTAssertEqual(try reopened.preference(for: record.id.description).preferredTargetID, "remote")
    }
    func sql(_ file: URL, _ command: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, command, nil, nil, nil), SQLITE_OK)
    }
    func testLegacyImportIsOneWayAndEmptySnapshotStaysEmpty() throws {
        let file = try folder().appendingPathComponent("catalog.sqlite")
        do {
            let store = try CatalogStore(url: file)
            XCTAssertNil(try store.importedGameDetails())
            XCTAssertTrue(try store.importGameDetailsOnce(["epic:42": Data("original".utf8)]))
            XCTAssertFalse(try store.importGameDetailsOnce(["epic:42": Data("stale".utf8)]))
            XCTAssertEqual(try store.importedGameDetails()?["epic:42"], Data("original".utf8))
            try store.replaceGameDetails([:])
        }
        let reopened = try CatalogStore(url: file)
        XCTAssertEqual(try reopened.importedGameDetails(), [:])
        XCTAssertFalse(try reopened.importGameDetailsOnce(["epic:42": Data("stale".utf8)]))
    }
    func testSchemaOneBackupPreservesCatalogAndPreferences() throws {
        let file = try folder().appendingPathComponent("catalog.sqlite")
        do {
            let store = try CatalogStore(url: file)
            try store.setPreference(.init(favorite: true), for: "epic:42")
        }
        try sql(file, "DROP TABLE game_details; DROP TABLE migrations; PRAGMA user_version=1")
        let store = try CatalogStore(url: file)
        XCTAssertTrue(try store.preference(for: "epic:42").favorite)
        XCTAssertNil(try store.importedGameDetails())
        let backup = file.appendingPathExtension("schema1-backup")
        let original = try Data(contentsOf: backup)
        try store.setPreference(.init(favorite: false), for: "epic:42")
        _ = try CatalogStore(url: file)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }
    func testSnapshotFailureRollsBackPreviousData() throws {
        let file = try folder().appendingPathComponent("catalog.sqlite")
        let store = try CatalogStore(url: file)
        let original = ["local:42": Data("retained".utf8)]
        try store.replaceGameDetails(original)
        try sql(file, "CREATE TRIGGER fail_insert BEFORE INSERT ON game_details BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        XCTAssertThrowsError(try store.replaceGameDetails(["local:43": Data("new".utf8)]))
        XCTAssertEqual(try store.importedGameDetails(), original)
    }
    func testFutureSchemaRemainsUntouched() throws {
        let file = try folder().appendingPathComponent("catalog.sqlite")
        try sql(file, "PRAGMA user_version=99")
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try CatalogStore(url: file))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testProfileRollbackAndClonePreserveOriginal() throws {
        let store = CompatibilityProfileStore(directory: try folder())
        let accepted = profile()
        try store.save(accepted)
        var changed = accepted; changed.arguments = ["-ResX=1280"]
        try store.save(changed)
        try store.rollback(accepted.profileID)
        XCTAssertEqual(try store.load(accepted.profileID), accepted)
        let clone = try store.clone(accepted.profileID, as: "steam-42-test")
        XCTAssertEqual(clone.validation, "testing")
        XCTAssertEqual(try store.load(accepted.profileID), accepted)
        XCTAssertThrowsError(try store.clone(accepted.profileID, as: "steam-42-test"))
    }
    func testProfileRejectsTraversalEnvironmentInjectionAndFutureSchema() throws {
        var candidate = profile(); candidate.profileID = "../escape"
        XCTAssertThrowsError(try candidate.validate())
        candidate = profile(); candidate.environment["DYLD_INSERT_LIBRARIES"] = "/tmp/evil"
        XCTAssertThrowsError(try candidate.validate())
        candidate = profile(); candidate.arguments = ["-ExecCmds=quit"]
        XCTAssertThrowsError(try candidate.validate())
        candidate = profile(); candidate.schemaVersion = 99
        XCTAssertThrowsError(try candidate.validate())
    }
    func testProfileImportRejectsOversize() throws {
        let store = CompatibilityProfileStore(directory: try folder())
        XCTAssertThrowsError(try store.decode(Data(repeating: 0, count: 65537)))
        XCTAssertEqual(try store.decode(JSONEncoder().encode(profile())), profile())
    }
    func testArtworkSupportsModernAndLegacyCacheWithoutEscapingRoot() throws {
        let root = try folder()
        let cache = root.appendingPathComponent("appcache/librarycache")
        let modern = cache.appendingPathComponent("42/library_600x900.jpg")
        try FileManager.default.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = cache.appendingPathComponent("42_library_600x900.jpg")
        try Data([1]).write(to: legacy)
        XCTAssertEqual(SteamNativeProvider.cachedArtwork(appID: "42", steamRoot: root), legacy.resolvingSymlinksInPath())
        try Data([2]).write(to: modern)
        XCTAssertEqual(SteamNativeProvider.cachedArtwork(appID: "42", steamRoot: root), modern.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: modern)
        let outside = root.appendingPathComponent("outside.jpg")
        try Data([3]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: modern, withDestinationURL: outside)
        XCTAssertEqual(SteamNativeProvider.cachedArtwork(appID: "42", steamRoot: root), legacy.resolvingSymlinksInPath())
        XCTAssertNil(SteamNativeProvider.cachedArtwork(appID: "../42", steamRoot: root))
    }
    func testWindowsManifestDiscoveryAndMissingProfile() throws {
        let root = try folder()
        let apps = root.appendingPathComponent("steamapps")
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("common/Synthetic"), withIntermediateDirectories: true)
        let manifest = "\"AppState\" { \"appid\" \"42\" \"name\" \"Synthetic\" \"installdir\" \"Synthetic\" \"StateFlags\" \"4\" \"LastUpdated\" \"0\" }"
        try manifest.write(to: apps.appendingPathComponent("appmanifest_42.acf"), atomically: true, encoding: .utf8)
        let configured = SteamWindowsProvider(steamRoot: root, profileIDs: ["42": "steam-42"]).scan()
        XCTAssertEqual(configured.records.count, 1)
        XCTAssertTrue(configured.records[0].launchTargets[0].available)
        XCTAssertFalse(SteamWindowsProvider(steamRoot: root).scan().records[0].launchTargets[0].available)
        try manifest.replacingOccurrences(of: "Synthetic\" \"StateFlags", with: "..\" \"StateFlags").write(to: apps.appendingPathComponent("appmanifest_42.acf"), atomically: true, encoding: .utf8)
        XCTAssertTrue(SteamWindowsProvider(steamRoot: root).scan().records.isEmpty)
    }
}
