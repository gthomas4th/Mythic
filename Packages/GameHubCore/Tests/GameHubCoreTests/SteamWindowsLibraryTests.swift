import Foundation
import XCTest
@testable import GameHubCore

final class SteamWindowsLibraryTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
    private func install(_ appID: String, at library: URL, title: String = "Synthetic") throws {
        let apps = library.appendingPathComponent("steamapps")
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("common/Fixture"), withIntermediateDirectories: true)
        let manifest = "\"AppState\" { \"appid\" \"\(appID)\" \"name\" \"\(title)\" \"installdir\" \"Fixture\" \"StateFlags\" \"4\" \"LastUpdated\" \"0\" }"
        try manifest.write(to: apps.appendingPathComponent("appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
    }
    func testMappedLibrariesAndDuplicatePreferPrimary() throws {
        let drive = try fixture()
        let primary = drive.appendingPathComponent("Steam")
        let secondary = drive.appendingPathComponent("Other Library")
        try install("42", at: primary, title: "Primary")
        try install("42", at: secondary, title: "Duplicate")
        try install("43", at: secondary)
        let vdf = #"""
        "libraryfolders" {
            "0" { "path" "C:\\Steam" }
            "1" { "path" "c:\\Other Library" }
            "2" "C:/Other Library"
        }
        """#
        try vdf.write(to: primary.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let result = SteamWindowsProvider(steamRoot: primary, profileIDs: ["43": "accepted"], driveRoots: ["C": drive]).scan()
        XCTAssertEqual(result.records.map(\.id.externalID), ["42", "43"])
        XCTAssertEqual(result.records.first?.title, "Primary")
        XCTAssertEqual(result.records.last?.launchTargets.first?.application, secondary.appendingPathComponent("steamapps/common/Fixture").resolvingSymlinksInPath())
        XCTAssertTrue(result.records.last?.launchTargets.first?.available == true)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }
    func testUnmappedTraversalAndSymlinkEscapeAreRejected() throws {
        let base = try fixture()
        let drive = base.appendingPathComponent("drive")
        let primary = drive.appendingPathComponent("Steam")
        let outside = base.appendingPathComponent("outside")
        try install("42", at: primary)
        try install("43", at: outside)
        try FileManager.default.createSymbolicLink(at: drive.appendingPathComponent("escape"), withDestinationURL: outside)
        let vdf = #"""
        "libraryfolders" {
            "1" { "path" "D:/outside" }
            "2" { "path" "C:/../outside" }
            "3" { "path" "C:/escape" }
            "4" { "path" "C:relative" }
            "5" { "path" "//server/share" }
        }
        """#
        try vdf.write(to: primary.appendingPathComponent("steamapps/libraryfolders.vdf"), atomically: true, encoding: .utf8)
        let result = SteamWindowsProvider(steamRoot: primary, driveRoots: ["c": drive]).scan()
        XCTAssertEqual(result.records.map(\.id.externalID), ["42"])
        XCTAssertEqual(result.diagnostics.filter { $0 == "windows-steam.library-unmapped-or-invalid" }.count, 5)
    }
    func testMalformedOrOversizedLibraryListKeepsPrimary() throws {
        let root = try fixture()
        try install("42", at: root)
        let file = root.appendingPathComponent("steamapps/libraryfolders.vdf")
        for contents in [Data("\"libraryfolders\" {".utf8), Data(repeating: 32, count: 8 * 1024 * 1024 + 1)] {
            try contents.write(to: file)
            let result = SteamWindowsProvider(steamRoot: root).scan()
            XCTAssertEqual(result.records.map(\.id.externalID), ["42"])
            XCTAssertTrue(result.diagnostics.contains("windows-steam.library-list-invalid"))
        }
    }
}
