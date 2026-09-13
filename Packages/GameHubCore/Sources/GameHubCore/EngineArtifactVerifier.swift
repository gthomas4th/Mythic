import Foundation
import CryptoKit

public enum EngineArtifactVerifier {
    public static func versionString(major: Int, minor: Int, patch: Int, preRelease: String = "", build: String = "") -> String {
        "\(major).\(minor).\(patch)" + (preRelease.isEmpty ? "" : "-" + preRelease) + (build.isEmpty ? "" : "+" + build)
    }

    /// Older official catalogs publish HTTP URLs; upgrade only the known engine host.
    public static func secureURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value),
              parts.host?.lowercased() == "dl.getmythic.app",
              parts.scheme == "https" || parts.scheme == "http",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.hasPrefix("/engine/") else { throw VerificationError.invalidSource }
        parts.scheme = "https"
        guard let url = parts.url else { throw VerificationError.invalidSource }
        return url
    }

    public static func checksum(_ data: Data) throws -> String {
        guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else {
            throw VerificationError.invalidChecksum
        }
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard (1...2).contains(fields.count), let value = fields.first, value.count == 64,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw VerificationError.invalidChecksum
        }
        return value.lowercased()
    }

    public static func verify(file: URL, expectedSHA256: String) throws {
        let expected = try checksum(Data(expectedSHA256.utf8))
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw VerificationError.mismatch }
    }

    public enum VerificationError: Error, LocalizedError {
        case invalidSource, invalidChecksum, missingChecksum, mismatch, existingDirectory, incompleteEngine
        public var errorDescription: String? {
            switch self {
            case .invalidSource: "The engine download must use the official HTTPS source."
            case .invalidChecksum: "The publisher's engine checksum is invalid. Nothing was installed."
            case .missingChecksum: "This engine release has no published checksum. Choose a release with verification metadata."
            case .mismatch: "The engine download did not match its published checksum. Nothing was installed. Try downloading it again."
            case .existingDirectory: "An engine folder already exists. It has been preserved; inspect or back it up before installing again."
            case .incompleteEngine: "The verified archive did not contain a complete engine. Nothing was installed."
            }
        }
    }
}
