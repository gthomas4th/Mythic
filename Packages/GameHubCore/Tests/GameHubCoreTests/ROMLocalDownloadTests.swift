import XCTest
@testable import GameHubCore

final class ROMLocalDownloadTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func put(_ text: String, _ path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func testSingleROMPreservesOriginalAndDoesNotOverwriteExistingDownload() throws {
        let source = try folder(), destination = try folder()
        try put("synthetic rom", "game.iso", in: source)
        let first = try ROMLocalDownload.copy(content: source.appendingPathComponent("game.iso"), sourceRoot: source, destinationParent: destination)
        let second = try ROMLocalDownload.copy(content: source.appendingPathComponent("game.iso"), sourceRoot: source, destinationParent: destination)
        XCTAssertNotEqual(first, second)
        for root in [source, first, second] {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("game.iso")), Data("synthetic rom".utf8))
        }
    }
    func testPlaylistCopiesAllPartsWithRelativeLayoutAndExcludesOtherGames() throws {
        let source = try folder(), destination = try folder()
        try put("disc.cue\nsecond.iso\n", "title/game.m3u", in: source)
        try put("FILE \"track.bin\" BINARY\n TRACK 01 MODE2/2352\n", "title/disc.cue", in: source)
        try put("track", "title/track.bin", in: source)
        try put("second", "title/second.iso", in: source)
        try put("unrelated", "other.iso", in: source)
        let copied = try ROMLocalDownload.copy(content: source.appendingPathComponent("title/game.m3u"), sourceRoot: source, destinationParent: destination)
        XCTAssertEqual(try ROMIndex.parts(of: copied.appendingPathComponent("title/game.m3u"), root: copied).count, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.appendingPathComponent("other.iso").path))
        XCTAssertEqual(try Data(contentsOf: copied.appendingPathComponent("title/track.bin")), Data("track".utf8))
    }
    func testInvalidReferencesLeaveDestinationEmpty() throws {
        let source = try folder(), destination = try folder()
        for reference in ["missing.iso", "../outside.iso"] {
            try put(reference, "bad.m3u", in: source)
            XCTAssertThrowsError(try ROMLocalDownload.copy(content: source.appendingPathComponent("bad.m3u"), sourceRoot: source, destinationParent: destination))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        }
    }
    func testPS3IncludesEntireDiscAndPreservesBootPath() throws {
        let source = try folder(), destination = try folder()
        try put("boot", "title/PS3_GAME/USRDIR/EBOOT.BIN", in: source)
        try put("asset", "title/PS3_GAME/USRDIR/data/asset.dat", in: source)
        try put("metadata", "title/PS3_DISC.SFB", in: source)
        let copied = try ROMLocalDownload.copy(content: source.appendingPathComponent("title/PS3_GAME/USRDIR/EBOOT.BIN"), sourceRoot: source, destinationParent: destination)
        XCTAssertEqual(try Data(contentsOf: copied.appendingPathComponent("title/PS3_GAME/USRDIR/data/asset.dat")), Data("asset".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.appendingPathComponent("title/PS3_DISC.SFB").path))
    }
    func testCancellationRemovesStagingAndPreservesSource() async throws {
        let source = try folder(), destination = try folder()
        try put("rom", "game.iso", in: source)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ROMLocalDownload.copy(content: source.appendingPathComponent("game.iso"), sourceRoot: source, destinationParent: destination)
        }
        do { _ = try await task.value; XCTFail("Cancelled copy must fail") }
        catch is CancellationError { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("game.iso")), Data("rom".utf8))
    }
}
