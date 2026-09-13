import Foundation
import XCTest
@testable import GameHubCore

final class ValveKeyValuesParserTests: XCTestCase {
    func testNestedCommentsEscapesAndUnicode() throws {
        let value = try ValveKeyValues.parse(#"""
        // header
        "LibraryFolders" { "0" { "path" "/Games/日本語" } title "A \"quote\" \\ path" }
        """#)
        let folders = try XCTUnwrap(value.object("libraryfolders"))
        XCTAssertEqual(try folders.object("0")?.string("path"), "/Games/日本語")
        XCTAssertEqual(try folders.string("title"), "A \"quote\" \\ path")
    }
    func testRepeatedKeysPreservedAndSingletonRejected() throws {
        let value = try ValveKeyValues.parse("id 1 ID 2")
        XCTAssertEqual(value.entries.count, 2)
        XCTAssertThrowsError(try value.string("id"))
    }
    func testMalformedDocumentsRejected() {
        for text in ["a {", "a", "}", "a { b }", "a \"unterminated", "a { b c }}", "#include file", "a b [$WIN32]"] {
            XCTAssertThrowsError(try ValveKeyValues.parse(text), text)
        }
    }
    func testDepthLimit() {
        XCTAssertThrowsError(try ValveKeyValues.parse(String(repeating: "a {", count: 66) + String(repeating: "}", count: 66)))
    }
    func testBOMEmptyAndAdjacentBraces() throws {
        XCTAssertEqual(try ValveKeyValues.parse("\u{feff} // empty").entries.count, 0)
        XCTAssertEqual(try ValveKeyValues.parse("a{b c}").object("a")?.string("b"), "c")
    }
}
final class GameIdentityTests: XCTestCase {
    func testSameTitleDoesNotDefineIdentity() {
        XCTAssertNotEqual(GameIdentity(provider: .steam, externalID: "1"), GameIdentity(provider: .epic, externalID: "1"))
        XCTAssertEqual(GameIdentity(provider: .steam, externalID: "1").description, "steam:1")
    }
    func testSteamLaunchIsValidated() {
        XCTAssertEqual(SteamLaunch.url(appID: "42")?.absoluteString, "steam://rungameid/42")
        for invalid in ["", "0", "01", "-1", "42/evil", "42?x=y", "4294967296"] {
            XCTAssertNil(SteamLaunch.url(appID: invalid))
        }
    }
}
final class SteamManifestDiscoveryTests: XCTestCase {
    private func temporary(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
    private func manifest(_ root: URL, id: String = "42", flags: String = "4", directory: String = "Fixture") throws {
        try write("AppState { appid \(id) name \"Fixture Game\" installdir \"\(directory)\" StateFlags \(flags) LastUpdated 123 }",
                  to: root.appendingPathComponent("steamapps/appmanifest_\(id).acf"))
    }
    private func application(_ root: URL, native: Bool = true) throws {
        let contents = root.appendingPathComponent("steamapps/common/Fixture/Fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleExecutable": "Fixture", "CFBundleSupportedPlatforms": ["MacOSX"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let executable = contents.appendingPathComponent("MacOS/Fixture")
        try Data(native ? [0xcf, 0xfa, 0xed, 0xfe, 12, 0, 0, 1] : [0x4d, 0x5a, 0, 0, 0, 0, 0, 0]).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func testModernMultipleLibrariesDeduplicateAndMissingArtwork() throws {
        try temporary { root in
            let primary = root.appendingPathComponent("Steam")
            let external = root.appendingPathComponent("External Games")
            try manifest(primary); try application(primary)
            try manifest(external); try application(external)
            try manifest(external, id: "43")
            try write("libraryfolders { 0 { path \"\(primary.path)\" } 1 { path \"\(external.path)\" } 2 { path \"\(external.path)\" } }",
                      to: primary.appendingPathComponent("steamapps/libraryfolders.vdf"))
            let result = SteamNativeProvider(steamRoot: primary).scan()
            XCTAssertEqual(result.records.map(\.id.description), ["steam:42", "steam:43"])
            XCTAssertEqual(result.manifests.count, 3)
            XCTAssertNil(result.records.first?.artwork)
            XCTAssertEqual(result.records.first?.launchTargets.first?.locator, SteamLaunch.url(appID: "42"))
            XCTAssertTrue(result.diagnostics.contains("steam:42.duplicate"))
        }
    }
    func testLegacyLibraryFoldersAndUnavailableRoot() throws {
        try temporary { root in
            let extra = root.appendingPathComponent("extra")
            try manifest(extra); try application(extra)
            try write("LibraryFolders { 1 \"\(extra.path)\" 2 \"\(root.path)/missing\" }",
                      to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
            let result = SteamNativeProvider(steamRoot: root).scan()
            XCTAssertEqual(result.records.count, 1)
            XCTAssertTrue(result.diagnostics.contains("library.unavailable"))
        }
    }
    func testPartialInstallAndWindowsPayloadExcluded() throws {
        try temporary { root in
            try manifest(root, flags: "6"); try application(root)
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
            try manifest(root); try application(root, native: false)
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
        }
    }
    func testMalformedSiblingAndLibraryConfigAreNonfatal() throws {
        try temporary { root in
            try manifest(root); try application(root)
            try write("AppState {", to: root.appendingPathComponent("steamapps/appmanifest_bad.acf"))
            try write("libraryfolders {", to: root.appendingPathComponent("steamapps/libraryfolders.vdf"))
            let result = SteamNativeProvider(steamRoot: root).scan()
            XCTAssertEqual(result.records.count, 1)
            XCTAssertEqual(result.diagnostics.count, 2)
        }
    }
    func testTraversalAndMismatchedAppIDRejected() throws {
        try temporary { root in
            try manifest(root, directory: "../outside"); try application(root)
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
            try manifest(root)
            try FileManager.default.moveItem(at: root.appendingPathComponent("steamapps/appmanifest_42.acf"),
                                            to: root.appendingPathComponent("steamapps/appmanifest_43.acf"))
            XCTAssertEqual(SteamNativeProvider(steamRoot: root).scan().diagnostics, ["manifest.identity-mismatch"])
        }
    }
    func testMetadataAndCachedArtwork() throws {
        try temporary { root in
            try manifest(root); try application(root)
            try write("synthetic image", to: root.appendingPathComponent("appcache/librarycache/42_library_600x900.jpg"))
            let result = SteamNativeProvider(steamRoot: root).scan()
            XCTAssertEqual(result.manifests.first?.lastUpdated, 123)
            XCTAssertEqual(result.manifests.first?.stateFlags, 4)
            XCTAssertEqual(result.manifests.first?.installDirectory, "Fixture")
            XCTAssertNotNil(result.records.first?.artwork)
        }
    }
    func testMissingPayloadAndAmbiguousIdentityRejected() throws {
        try temporary { root in
            try manifest(root)
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
            XCTAssertThrowsError(try SteamManifest(text: "AppState { appid 42 appid 43 }", libraryRoot: root))
        }
    }
    func testUnrelatedHelperBundleDoesNotProveNativeGame() throws {
        try temporary { root in
            try manifest(root); try application(root)
            let payload = root.appendingPathComponent("steamapps/common/Fixture")
            try FileManager.default.moveItem(at: payload.appendingPathComponent("Fixture.app"),
                                            to: payload.appendingPathComponent("CrashReporter.app"))
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
        }
    }
    func testSymlinkCannotEscapePayload() throws {
        try temporary { root in
            let outside = root.appendingPathComponent("outside")
            try manifest(outside); try application(outside)
            let steam = root.appendingPathComponent("Steam")
            try manifest(steam)
            let common = steam.appendingPathComponent("steamapps/common")
            try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: common.appendingPathComponent("Fixture"),
                withDestinationURL: outside.appendingPathComponent("steamapps/common/Fixture"))
            XCTAssertTrue(SteamNativeProvider(steamRoot: steam).scan().records.isEmpty)
        }
    }
    func testUniversalArchitectureAndTruncatedHeader() throws {
        try temporary { root in
            try manifest(root); try application(root)
            let binary = root.appendingPathComponent("steamapps/common/Fixture/Fixture.app/Contents/MacOS/Fixture")
            let header: [UInt8] = [0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 1, 1, 0, 0, 12] + Array(repeating: 0, count: 16)
            try Data(header).write(to: binary)
            XCTAssertEqual(SteamNativeProvider(steamRoot: root).scan().records.count, 1)
            try Data(header.prefix(8)).write(to: binary)
            XCTAssertTrue(SteamNativeProvider(steamRoot: root).scan().records.isEmpty)
        }
    }

}
