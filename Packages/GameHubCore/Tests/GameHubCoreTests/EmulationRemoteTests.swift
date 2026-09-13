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
    func testDolphinPresetsKeepContentAsOneArgument() throws {
        let content = URL(fileURLWithPath: "/games/A game; $(ignored).rvz")
        let args = try EmulatorCommand.arguments(kind: .dolphin, content: content, dolphinPreset: .metal1080)
        XCTAssertEqual(Array(args.suffix(2)), ["-e", content.path])
        XCTAssertTrue(args.contains("GFX.Settings.InternalResolution=3"))
        XCTAssertTrue(args.contains("Metal"))
        let defaults = try EmulatorCommand.arguments(kind: .dolphin, content: content)
        XCTAssertFalse(defaults.contains("Metal"))
        XCTAssertFalse(defaults.contains(where: { $0.contains("InternalResolution") }))
        XCTAssertThrowsError(try EmulatorCommand.arguments(kind: .dolphin, content: XCTUnwrap(URL(string: "https://example.com/game.iso"))))
    }
    func testGameCubeFormatsAreIndexedAndStableWhenRenamed() throws {
        let root = try folder()
        try Data([7, 8, 9]).write(to: root.appendingPathComponent("Game.rvz"))
        try Data([4, 5, 6]).write(to: root.appendingPathComponent("Disc.gcm"))
        try Data([1]).write(to: root.appendingPathComponent("Not extracted.zip"))
        var index = ROMIndex(); try index.scan(root: root, system: "gc")
        XCTAssertEqual(index.entries.count, 2)
        let ids = Set(index.entries.map(\.id))
        try FileManager.default.moveItem(at: root.appendingPathComponent("Game.rvz"), to: root.appendingPathComponent("Renamed.rvz"))
        try index.scan(root: root, system: "gc")
        XCTAssertEqual(Set(index.entries.map(\.id)), ids)
    }
    func testEmulatorVersionReadDoesNotExecuteApplication() throws {
        let app = try fixtureEmulator()
        let info = try EmulatorApplicationInfo.inspect(application: app)
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.bundleIdentifier, "test.emulator")
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/emulator"))
        XCTAssertThrowsError(try EmulatorApplicationInfo.inspect(application: app))
    }
    func testEmulatorExecutableTraversalAndSymlinkEscapeFail() throws {
        let app = try fixtureEmulator()
        let executable = app.appendingPathComponent("Contents/MacOS/emulator")
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
        XCTAssertThrowsError(try EmulatorApplicationInfo.inspect(application: app))
        let info: [String: Any] = ["CFBundleExecutable": "../../../bin/sh"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try EmulatorApplicationInfo.inspect(application: app))
    }
    private func fixtureEmulator() throws -> URL {
        let app = try folder().appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleExecutable": "emulator", "CFBundleShortVersionString": "1.2.3", "CFBundleIdentifier": "test.emulator"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/emulator")
        try Data("This fixture must never execute".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return app
    }
}
