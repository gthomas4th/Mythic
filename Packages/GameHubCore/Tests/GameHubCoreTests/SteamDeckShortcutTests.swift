import Foundation
import XCTest
@testable import GameHubCore

final class SteamDeckShortcutTests: XCTestCase {
    private let device = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private func string(_ key: String, _ value: String) -> [UInt8] { [1] + Array((key + "\0" + value + "\0").utf8) }
    private func integer(_ key: String, _ value: UInt32) -> [UInt8] {
        [2] + Array((key + "\0").utf8) + (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    private func object(_ key: String, _ values: [UInt8]) -> [UInt8] { [0] + Array((key + "\0").utf8) + values + [8] }
    private func entry(_ index: String = "0", id: UInt32 = 2_500_000_000, title: String = "Example", options: String = "") -> [UInt8] {
        object(index, integer("appid", id) + string("AppName", title) + string("Exe", "/usr/bin/emulator")
               + string("LaunchOptions", options) + object("tags", string("0", "Favorites")))
    }
    private func file(_ values: [UInt8]) -> Data { Data(object("shortcuts", values) + [8]) }

    func testEmptyExport() throws {
        XCTAssertTrue(try SteamShortcutImporter.parse(file([]), deviceID: device).isEmpty)
    }

    func testROMReferenceWithSpacesAndUnicode() throws {
        let path = "/run/media/deck/Card/Emulation/roms/ps2/Example 日本.chd"
        let result = try SteamShortcutImporter.parse(file(entry(title: "日本", options: "--fullscreen \"\(path)\"")), deviceID: device)
        XCTAssertEqual(result.first?.romPath, path)
        XCTAssertEqual(result.first?.title, "日本")
        XCTAssertTrue(result[0].id.hasPrefix("shortcut:"))
        XCTAssertNotEqual(result[0].id, GameIdentity(provider: .steam, externalID: "2500000000").description)
    }

    func testUnresolvedShortcutDoesNotGuessFromTitle() throws {
        let result = try SteamShortcutImporter.parse(file(entry(title: "RetroArch ROM", options: "--fullscreen")), deviceID: device)
        XCTAssertFalse(result[0].isROMReference)
    }

    func testCommandsAndAmbiguousPathsAreNeverResolved() throws {
        let cases = ["\"$(touch /tmp/never-run)/Emulation/roms/ps2/game.iso\"",
                     "/home/deck/Emulation/roms/ps2/../game.iso",
                     "\"/home/deck/Emulation/roms/ps2/game.iso",
                     "/home/deck/Emulation/roms/ps2/a.iso /home/deck/Emulation/roms/ps2/b.iso"]
        for options in cases {
            XCTAssertNil(try SteamShortcutImporter.parse(file(entry(options: options)), deviceID: device)[0].romPath)
        }
    }

    func testIdentityIsDeviceScopedAndNeverTitleMerged() throws {
        let data = file(entry("0", id: 1, title: "Same") + entry("1", id: 2, title: "Same"))
        let first = try SteamShortcutImporter.parse(data, deviceID: device)
        let second = try SteamShortcutImporter.parse(data, deviceID: UUID())
        XCTAssertEqual(first.count, 2)
        XCTAssertNotEqual(first[0].id, first[1].id)
        XCTAssertNotEqual(first[0].id, second[0].id)
    }

    func testTruncatedAndTrailingDataRejected() {
        let valid = file(entry())
        for length in 0..<valid.count {
            XCTAssertThrowsError(try SteamShortcutImporter.parse(valid.prefix(length), deviceID: device))
        }
        XCTAssertThrowsError(try SteamShortcutImporter.parse(valid + Data([8]), deviceID: device))
    }

    func testDuplicateKeysAndIDsRejected() {
        let fields = integer("appid", 1) + string("AppName", "A") + string("appname", "B")
        XCTAssertThrowsError(try SteamShortcutImporter.parse(file(object("0", fields)), deviceID: device))
        XCTAssertThrowsError(try SteamShortcutImporter.parse(file(entry("0", id: 1) + entry("1", id: 1)), deviceID: device))
    }

    func testUnknownTypeAndLimitsRejected() {
        XCTAssertThrowsError(try SteamShortcutImporter.parse(file([5] + Array("wide\0".utf8)), deviceID: device))
        XCTAssertThrowsError(try SteamShortcutImporter.parse(Data(repeating: 0, count: SteamShortcutImporter.maximumBytes + 1), deviceID: device))
        var nested: [UInt8] = []
        for _ in 0..<34 { nested = object("nested", nested) }
        XCTAssertThrowsError(try SteamShortcutImporter.parse(file(nested), deviceID: device))
    }

    func testReimportIsIdempotentAndPreservesAbsentReferences() throws {
        let first = try SteamShortcutImporter.parse(file(entry("0", id: 1) + entry("1", id: 2)), deviceID: device)
        let inventory = try SteamDeckInventory(deviceID: device).merging(first)
        let update = try SteamShortcutImporter.parse(file(entry(id: 1, title: "Renamed")), deviceID: device)
        let merged = try inventory.merging(update).merging(update)
        XCTAssertEqual(merged.shortcuts.count, 2)
        XCTAssertEqual(merged.shortcuts.first(where: { $0.shortcutID == 1 })?.title, "Renamed")
        let restored = try SteamDeckInventory.decode(JSONEncoder().encode(merged))
        XCTAssertEqual(restored.shortcuts, merged.shortcuts)
        XCTAssertEqual(restored.deviceID, device)
    }

    func testWrongDeviceAndFutureSchemaPreserveInventory() throws {
        let imported = try SteamShortcutImporter.parse(file(entry()), deviceID: UUID())
        XCTAssertThrowsError(try SteamDeckInventory(deviceID: device).merging(imported))
        var future = SteamDeckInventory(deviceID: device)
        future.schemaVersion = 2
        XCTAssertThrowsError(try SteamDeckInventory.decode(JSONEncoder().encode(future)))
    }
}
