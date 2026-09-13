import Foundation

/// Ordered entries preserve repeated keys; consumers reject ambiguous singleton fields.
public struct ValveKeyValues: Sendable, Equatable {
    public indirect enum Value: Sendable, Equatable {
        case string(String)
        case object(ValveKeyValues)
    }
    public struct Entry: Sendable, Equatable {
        public let key: String
        public let value: Value
    }
    public let entries: [Entry]
    public enum ParseError: Error { case malformed, limitExceeded, ambiguousKey }

    public func value(_ key: String) throws -> Value? {
        let matches = entries.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        guard matches.count <= 1 else { throw ParseError.ambiguousKey }
        return matches.first?.value
    }
    public func string(_ key: String) throws -> String? {
        guard case .string(let text) = try value(key) else { return nil }
        return text
    }
    public func object(_ key: String) throws -> ValveKeyValues? {
        guard case .object(let object) = try value(key) else { return nil }
        return object
    }
    public static func parse(_ text: String) throws -> Self {
        guard text.utf8.count <= 8 * 1024 * 1024 else { throw ParseError.limitExceeded }
        var parser = Parser(chars: Array(text))
        return try parser.object(nested: false, depth: 0)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        mutating func skipWhitespace() {
            while index < chars.count {
                if chars[index].isWhitespace || chars[index] == "\u{feff}" { index += 1 } else if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count && chars[index] != "\n" { index += 1 }
                } else { break }
            }
        }
        mutating func token() throws -> String {
            skipWhitespace()
            guard index < chars.count, chars[index] != "{", chars[index] != "}" else { throw ParseError.malformed }
            var result = ""
            if chars[index] == "\"" {
                index += 1
                while index < chars.count {
                    let char = chars[index]
                    index += 1
                    if char == "\"" { return result }
                    if char == "\\" {
                        guard index < chars.count else { throw ParseError.malformed }
                        let escaped = chars[index]
                        index += 1
                        switch escaped {
                        case "\\", "\"": result.append(escaped)
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        case "r": result.append("\r")
                        default: result.append("\\"); result.append(escaped)
                        }
                    } else { result.append(char) }
                }
                throw ParseError.malformed
            }
            while index < chars.count, !chars[index].isWhitespace, chars[index] != "{", chars[index] != "}" {
                guard chars[index] != "\"" else { throw ParseError.malformed }
                if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" { break }
                result.append(chars[index]); index += 1
            }
            guard !result.isEmpty else { throw ParseError.malformed }
            return result
        }
        mutating func object(nested: Bool, depth: Int) throws -> ValveKeyValues {
            guard depth <= 64 else { throw ParseError.limitExceeded }
            var entries: [Entry] = []
            while true {
                skipWhitespace()
                if index == chars.count {
                    guard !nested else { throw ParseError.malformed }
                    return .init(entries: entries)
                }
                if chars[index] == "}" {
                    guard nested else { throw ParseError.malformed }
                    index += 1
                    return .init(entries: entries)
                }
                let key = try token()
                // Includes, inheritance and platform conditions are not supported in manifest mode.
                guard !key.hasPrefix("#"), !key.hasPrefix("[") else { throw ParseError.malformed }
                skipWhitespace()
                let value: Value
                if index < chars.count, chars[index] == "{" {
                    index += 1
                    value = .object(try object(nested: true, depth: depth + 1))
                } else { value = .string(try token()) }
                entries.append(.init(key: key, value: value))
            }
        }
    }
}
