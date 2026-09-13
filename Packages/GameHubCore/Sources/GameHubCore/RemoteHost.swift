import Foundation

public struct RemoteHost: Codable, Sendable {
    public var name: String
    public var address: String
    public var application: String
    public func validate() throws {
        guard !address.isEmpty, address.count <= 253, !address.hasPrefix("-"),
              address.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ".:-".unicodeScalars.contains($0) }),
              !application.isEmpty, application.count <= 200, !application.hasPrefix("-"),
              !application.contains("\n"), !application.contains("\0") else { throw RemoteError.invalid }
    }
    public var arguments: [String] { ["stream", address, application, "--resolution", "1920x1080", "--fps", "60", "--bitrate", "20000", "--no-hdr"] }
    public enum RemoteError: LocalizedError {
        case invalid
        public var errorDescription: String? { "Enter a valid host name or address and Sunshine application name." }
    }
}
public enum RemoteHealthClassifier {
    public static func description(reachable: Bool, relayed: Bool?, milliseconds: Double?) -> String {
        guard reachable else { return "Offline or streaming service unavailable" }
        if relayed == true { return "Relayed connection — streaming quality may be limited" }
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return "Reachable — stream quality untested" }
        return "Streaming port reachable · " + String(format: "%.0f ms connection time", milliseconds) + " · stream quality untested"
    }
}
