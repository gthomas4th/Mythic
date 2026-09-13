import Foundation

/// Value accumulator used under a lock by Legendary's two output streams.
public struct LegendaryInstallMetadata: Sendable {
    public private(set) var installSize: Int64?
    public private(set) var optionalPacks: [String: String] = [:]
    public init() {}

    /// Returns true once Legendary has supplied the requested metadata.
    public mutating func consume(_ line: String, isStandardError: Bool) -> Bool {
        if isStandardError {
            if let regex = try? Regex(#"Install size: (\d+(?:\.\d+)?) MiB"#),
               let match = try? regex.firstMatch(in: line),
               let sizeString = match[1].substring, let size = Double(sizeString),
               size.isFinite, size >= 0, size * 1_048_576 < Double(Int64.max) {
                installSize = Int64(size * 1_048_576)
                return true
            }
        } else {
            if let regex = try? Regex(#"\s*\* (?<identifier>\w+) - (?<name>.+)"#),
               let match = try? regex.firstMatch(in: line),
               let identifier = match["identifier"]?.substring, let name = match["name"]?.substring {
                optionalPacks[String(identifier)] = String(name)
            }
            return line.contains("Please enter tags of pack(s) to install")
        }
        return false
    }
}
