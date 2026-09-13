import Foundation
import XCTest
@testable import GameHubCore

final class EngineArtifactVerifierTests: XCTestCase {
    func testReceiptVersionRetainsPatchAndBuildMetadata() {
        XCTAssertEqual(EngineArtifactVerifier.versionString(major: 2, minor: 6, patch: 1, build: "0"), "2.6.1+0")
        XCTAssertEqual(EngineArtifactVerifier.versionString(major: 2, minor: 6, patch: 0), "2.6.0")
        XCTAssertEqual(EngineArtifactVerifier.versionString(major: 3, minor: 0, patch: 1, preRelease: "preview"), "3.0.1-preview")
    }

    func testOnlyOfficialURLsAreUpgraded() throws {
        XCTAssertEqual(try EngineArtifactVerifier.secureURL("http://dl.getmythic.app/engine/Engine.tar.xz").scheme, "https")
        for value in ["https://example.com/engine/file", "file:///tmp/engine", "http://dl.getmythic.app.example.com/engine/file",
                      "https://user:password@dl.getmythic.app/engine/file", "https://dl.getmythic.app:8080/engine/file",
                      "https://dl.getmythic.app/other/file", "https://dl.getmythic.app/engine/file?token=example"] {
            XCTAssertThrowsError(try EngineArtifactVerifier.secureURL(value))
        }
    }

    func testChecksumFormatsAndMalformedData() throws {
        let expected = String(repeating: "a", count: 64)
        XCTAssertEqual(try EngineArtifactVerifier.checksum(Data((expected.uppercased() + "  Engine.tar.xz\n").utf8)), expected)
        XCTAssertEqual(try EngineArtifactVerifier.checksum(Data(expected.utf8)), expected)
        for value in ["", "abc", String(repeating: "g", count: 64), expected + " file extra"] {
            XCTAssertThrowsError(try EngineArtifactVerifier.checksum(Data(value.utf8)))
        }
        XCTAssertThrowsError(try EngineArtifactVerifier.checksum(Data(repeating: 65, count: 4097)))
    }

    func testArtifactHashMustMatchBeforeUse() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        try EngineArtifactVerifier.verify(file: file, expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertThrowsError(try EngineArtifactVerifier.verify(file: file, expectedSHA256: String(repeating: "0", count: 64)))
    }
}
