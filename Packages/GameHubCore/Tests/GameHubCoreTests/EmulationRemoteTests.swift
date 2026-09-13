import XCTest
@testable import GameHubCore

final class EmulationRemoteTests: XCTestCase {
    func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testPlaylistGroupsDiscsAndRescanIsStable() throws {
        let root = try folder()
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("disc1.bin"))
        try Data([4, 5, 6]).write(to: root.appendingPathComponent("disc2.iso"))
        try "FILE \"disc1.bin\" BINARY\n TRACK 01 MODE2/2352\n".write(to: root.appendingPathComponent("disc1.cue"), atomically: true, encoding: .utf8)
        try "# two discs\ndisc1.cue\ndisc2.iso\n".write(to: root.appendingPathComponent("game.m3u"), atomically: true, encoding: .utf8)
        var index = ROMIndex(); try index.scan(root: root, system: "ps1")
        XCTAssertEqual(index.entries.count, 1)
        let id = index.entries.first?.id
        try index.scan(root: root, system: "ps1")
        XCTAssertEqual(index.entries.first?.id, id)
        try FileManager.default.moveItem(at: root.appendingPathComponent("game.m3u"), to: root.appendingPathComponent("renamed.m3u"))
        try index.scan(root: root, system: "ps1")
        XCTAssertEqual(index.entries.first?.id, id)
    }
    func testPlaylistTraversalAndCyclesFail() throws {
        let root = try folder()
        let file = root.appendingPathComponent("bad.m3u")
        try "../outside.iso".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ROMIndex.parts(of: file, root: root))
        try "bad.m3u".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ROMIndex.parts(of: file, root: root))
    }
    func testMissingDiscPreservesPreviousIndex() throws {
        let root = try folder()
        let rom = root.appendingPathComponent("good.iso")
        try Data([1]).write(to: rom)
        var index = ROMIndex(); try index.scan(root: root, system: "ps2")
        let id = index.entries.first?.id
        try "missing.iso".write(to: root.appendingPathComponent("bad.m3u"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try index.scan(root: root, system: "ps2"))
        XCTAssertEqual(index.entries.first?.id, id)
    }
    func testEmulatorArgumentsDoNotUseShellAndRequireCore() throws {
        let content = URL(fileURLWithPath: "/games/space name;ignored.iso")
        XCTAssertEqual(try EmulatorCommand.arguments(kind: .pcsx2, content: content), ["-batch", "-fullscreen", "--", content.path])
        XCTAssertThrowsError(try EmulatorCommand.arguments(kind: .retroArch, content: content))
        XCTAssertEqual(try EmulatorCommand.arguments(kind: .retroArch, content: content, core: URL(fileURLWithPath: "/cores/test.dylib")).last, content.path)
    }
    func testRemoteInputAndHealthDoNotClaimQuality() throws {
        let valid = RemoteHost(name: "PC", address: "yoda.local", application: "Desktop")
        XCTAssertNoThrow(try valid.validate())
        XCTAssertTrue(valid.arguments.contains("--no-hdr"))
        XCTAssertEqual(valid.arguments.prefix(3), ["stream", "yoda.local", "Desktop"])
        XCTAssertThrowsError(try RemoteHost(name: "PC", address: "--evil", application: "Desktop").validate())
        XCTAssertThrowsError(try RemoteHost(name: "PC", address: "pc;bad", application: "Desktop").validate())
        XCTAssertTrue(RemoteHealthClassifier.description(reachable: true, relayed: true, milliseconds: 10).contains("Relayed"))
        XCTAssertTrue(RemoteHealthClassifier.description(reachable: true, relayed: nil, milliseconds: 10).contains("untested"))
        XCTAssertTrue(RemoteHealthClassifier.description(reachable: false, relayed: false, milliseconds: 10).contains("unavailable"))
    }
}
