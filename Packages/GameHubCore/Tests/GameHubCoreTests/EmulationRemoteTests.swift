import XCTest
@testable import GameHubCore

final class EmulationRemoteTests: XCTestCase {
    func testROMTitleArticleNormalization() {
        XCTAssertEqual(ROMTitle.displayName("Addams Family, The"), "The Addams Family")
        XCTAssertEqual(ROMTitle.displayName("Legend of Zelda, The - Majora's Mask"), "The Legend of Zelda - Majora's Mask")
        XCTAssertEqual(ROMTitle.displayName("[Krnl.vip] SUPER MARIO ODYSSEY [0100000000010000] [v262144] (1G+1U)"), "SUPER MARIO ODYSSEY")
        XCTAssertEqual(ROMTitle.displayName("Legend of Zelda, The (USA) [Rev 1]"), "The Legend of Zelda")
        XCTAssertEqual(ROMTitle.displayName("Game - [Prototype]"), "Game")
        XCTAssertEqual(ROMTitle.displayName("Baten Kaitos (Disc 1)(USA)"), "Baten Kaitos (Disc 1)")
        XCTAssertEqual(ROMTitle.displayName("Altered Beast (Enhanced Colors)"), "Altered Beast (Enhanced Colors)")
        XCTAssertEqual(ROMTitle.sortKey("The Addams Family"), "Addams Family, The")
        XCTAssertTrue(ROMTitle.lookupNames("The Addams Family").contains("Addams Family, The"))
    }

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
        let session = URL(fileURLWithPath: "/Game Hub/session.cfg")
        let retroArch = try EmulatorCommand.arguments(kind: .retroArch, content: content,
            core: URL(fileURLWithPath: "/cores/test.dylib"), sessionConfiguration: session)
        XCTAssertTrue(retroArch.contains("--appendconfig=/Game Hub/session.cfg"))
        XCTAssertEqual(retroArch.last, content.path)
        XCTAssertEqual(try EmulatorCommand.arguments(kind: .rpcs3, content: content),
                       ["--no-gui", "--fullscreen", content.path])
    }
    func testSwitchFormatsAndDirectLaunchPreservePaths() throws {
        let root = try folder()
        let game = root.appendingPathComponent("Switch Game [USA]; sample.xci")
        try Data([1, 2, 3]).write(to: game)
        try Data([4, 5, 6]).write(to: root.appendingPathComponent("Other.nsp"))
        try Data([7]).write(to: root.appendingPathComponent("prod.keys"))
        var index = ROMIndex(); try index.scan(root: root, system: "switch")
        XCTAssertEqual(index.entries.count, 2)
        XCTAssertEqual(Set(index.entries.map { URL(fileURLWithPath: $0.relativePath).pathExtension }), ["xci", "nsp"])
        XCTAssertEqual(try EmulatorCommand.arguments(kind: .ryujinx, content: game), ["--no-gui", game.path])
        XCTAssertThrowsError(try EmulatorCommand.arguments(kind: .ryujinx, content: XCTUnwrap(URL(string: "https://example.com/game.xci"))))
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
        XCTAssertTrue(args.contains("Graphics.Settings.InternalResolution=3"))
        XCTAssertTrue(args.contains("Dolphin.Interface.ConfirmStop=False"))
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
    func testAdditionalImagesExcludeArchivesAndLooseTracks() throws {
        let root = try folder()
        for (index, ext) in ["pbp", "v64", "gen", "md", "smd", "32x", "zip", "bin", "raw"].enumerated() {
            try Data([UInt8(index)]).write(to: root.appendingPathComponent("Game.\(ext)"))
        }
        var index = ROMIndex(); try index.scan(root: root, system: "retro")
        XCTAssertEqual(index.entries.count, 6)
        XCTAssertFalse(index.entries.contains { ["zip", "bin", "raw"].contains(URL(fileURLWithPath: $0.relativePath).pathExtension) })
    }
    func testGDIGroupsTracksAndIdentityIncludesLayoutNotNames() throws {
        let root = try folder()
        for (trackIndex, name) in ["track one.bin", "audio.raw", "data.bin"].enumerated() {
            try Data([UInt8(trackIndex)]).write(to: root.appendingPathComponent(name))
        }
        let descriptor = root.appendingPathComponent("Game.gdi")
        let text = "3\n1 0 4 2352 \"track one.bin\" 0\n2 450 0 2352 audio.raw 0\n3 45000 4 2352 data.bin 0\n"
        try text.write(to: descriptor, atomically: true, encoding: .utf8)
        var index = ROMIndex(); try index.scan(root: root, system: "dreamcast")
        XCTAssertEqual(index.entries.count, 1)
        let id = index.entries.first?.id
        try FileManager.default.moveItem(at: root.appendingPathComponent("track one.bin"), to: root.appendingPathComponent("renamed.bin"))
        try text.replacingOccurrences(of: "track one.bin", with: "renamed.bin").write(to: descriptor, atomically: true, encoding: .utf8)
        try index.scan(root: root, system: "dreamcast")
        XCTAssertEqual(index.entries.first?.id, id)
        try text.replacingOccurrences(of: "track one.bin", with: "renamed.bin").replacingOccurrences(of: "2 450 ", with: "2 600 ").write(to: descriptor, atomically: true, encoding: .utf8)
        try index.scan(root: root, system: "dreamcast")
        XCTAssertNotEqual(index.entries.first?.id, id)
        try "Game.gdi\n".write(to: root.appendingPathComponent("Collection.m3u"), atomically: true, encoding: .utf8)
        try index.scan(root: root, system: "dreamcast")
        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries.first?.relativePath, "Collection.m3u")
    }
    func testGDIRejectsMalformedMissingAndEscapingTracks() throws {
        let root = try folder()
        let descriptor = root.appendingPathComponent("bad.gdi")
        let base = "3\n1 0 4 2352 first.bin 0\n2 450 0 2352 audio.raw 0\n3 45000 4 2352 last.bin 0\n"
        for name in ["first.bin", "audio.raw", "last.bin"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
        for text in [base.replacingOccurrences(of: "3\n", with: "4\n"), base.replacingOccurrences(of: "2 450", with: "1 450"), base.replacingOccurrences(of: "2352", with: "99"), base.replacingOccurrences(of: "first.bin", with: "../outside.bin"), base.replacingOccurrences(of: "first.bin", with: "missing.bin"), String(repeating: "x", count: 16384)] {
            try text.write(to: descriptor, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try ROMIndex.parts(of: descriptor, root: root))
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("first.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("first.bin"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try base.write(to: descriptor, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ROMIndex.parts(of: descriptor, root: root))
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
