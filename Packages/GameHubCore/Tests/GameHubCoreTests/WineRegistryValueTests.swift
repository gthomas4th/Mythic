import XCTest
@testable import GameHubCore

final class WineRegistryValueTests: XCTestCase {
    func testRetinaValueIsNotTheWholeLine() {
        XCTAssertEqual(WineRegistryValue.parse("\r\nHKEY_CURRENT_USER\\Software\\Wine\\Mac Driver\r\n    RetinaMode    REG_SZ    y\r\n", name: "RetinaMode", type: "REG_SZ"), "y")
        XCTAssertEqual(WineRegistryValue.parse("\tretinamode\tREG_SZ\tn\r\n", name: "RetinaMode", type: "REG_SZ"), "n")
    }
    func testDisplayScalingAndStrings() {
        XCTAssertEqual(WineRegistryValue.parse("    LogPixels    REG_DWORD    0xc0\n", name: "LogPixels", type: "REG_DWORD"), "0xc0")
        XCTAssertEqual(WineRegistryValue.parse("Display Name    REG_SZ    A value with spaces\n", name: "Display Name", type: "REG_SZ"), "A value with spaces")
    }
    func testWrongFieldsAndAmbiguityAreRejected() {
        XCTAssertNil(WineRegistryValue.parse("RetinaModeBackup REG_SZ y", name: "RetinaMode", type: "REG_SZ"))
        XCTAssertNil(WineRegistryValue.parse("RetinaMode REG_DWORD 1", name: "RetinaMode", type: "REG_SZ"))
        XCTAssertNil(WineRegistryValue.parse("RetinaMode REG_SZ y\nRetinaMode REG_SZ n", name: "RetinaMode", type: "REG_SZ"))
        XCTAssertNil(WineRegistryValue.parse("ERROR: The system was unable to find the specified registry key or value.", name: "RetinaMode", type: "REG_SZ"))
    }
}
