import Foundation

/// Imported references are device-scoped non-Steam entries, never Steam store app IDs.
public struct SteamDeckShortcut: Codable, Hashable, Identifiable, Sendable {
    public let deviceID: UUID
    public let shortcutID: UInt32
    public let title: String
    public let romPath: String?
    public var id: String { "shortcut:\(deviceID.uuidString.lowercased()):\(shortcutID)" }
    public var isROMReference: Bool { romPath != nil }
}

public struct SteamDeckInventory: Codable, Sendable {
    public var schemaVersion = 1
    public let deviceID: UUID
    public private(set) var shortcuts: [SteamDeckShortcut]

    public init(deviceID: UUID = UUID(), shortcuts: [SteamDeckShortcut] = []) {
        self.deviceID = deviceID
        self.shortcuts = shortcuts
    }

    /// Missing entries in a later export remain visible until deliberately removed.
    public func merging(_ incoming: [SteamDeckShortcut]) throws -> Self {
        guard schemaVersion == 1, incoming.allSatisfy({ $0.deviceID == deviceID }) else {
            throw SteamShortcutImportError.invalidInventory
        }
        var merged = Dictionary(shortcuts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in incoming { merged[item.id] = item }
        return .init(deviceID: deviceID, shortcuts: merged.values.sorted { $0.id < $1.id })
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= SteamShortcutImporter.maximumBytes else { throw SteamShortcutImportError.tooLarge }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1,
              result.shortcuts.allSatisfy({ $0.deviceID == result.deviceID }),
              Set(result.shortcuts.map(\.id)).count == result.shortcuts.count else {
            throw SteamShortcutImportError.invalidInventory
        }
        return result
    }
}

public enum SteamShortcutImportError: Error, LocalizedError {
    case tooLarge, malformed, unsupportedType, invalidInventory
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "This shortcut file is too large to import safely (8 MB limit)."
        case .malformed: "This is not a complete Steam shortcuts.vdf file. Copy it again after closing Steam on the Deck."
        case .unsupportedType: "This shortcut file uses an unsupported format. Your existing inventory was kept."
        case .invalidInventory: "The saved Deck inventory could not be read. It has not been overwritten."
        }
    }
}

public enum SteamShortcutImporter {
    public static let maximumBytes = 8_000_000

    public static func parse(_ data: Data, deviceID: UUID) throws -> [SteamDeckShortcut] {
        guard data.count <= maximumBytes else { throw SteamShortcutImportError.tooLarge }
        var reader = BinaryShortcutReader(bytes: Array(data))
        let root = try reader.object(depth: 0)
        guard reader.isFinished, root.count == 1, case .object(let entries)? = root["shortcuts"] else {
            throw SteamShortcutImportError.malformed
        }
        var seen = Set<UInt32>()
        var result: [SteamDeckShortcut] = []
        for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
            guard UInt32(key) != nil, case .object(let fields) = value,
                  case .integer(let identifier)? = fields["appid"], identifier != 0,
                  seen.insert(identifier).inserted,
                  case .string(let title)? = fields["appname"],
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.count <= 512 else { throw SteamShortcutImportError.malformed }
            let launchOptions: String
            switch fields["launchoptions"] {
            case .string(let value): launchOptions = value
            case nil: launchOptions = ""
            default: throw SteamShortcutImportError.malformed
            }
            result.append(.init(deviceID: deviceID, shortcutID: identifier, title: title,
                                romPath: romReference(in: launchOptions)))
        }
        return result
    }

    /// Recognize a literal EmuDeck ROM path only. Never execute or expand shortcut commands.
    private static func romReference(in options: String) -> String? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in options {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        guard quote == nil, !escaped else { return nil }
        if !current.isEmpty { tokens.append(current) }
        let extensions: Set<String> = ["nes", "sfc", "smc", "gb", "gbc", "gba", "nds", "3ds", "n64", "z64", "v64",
                                       "iso", "chd", "cue", "bin", "gdi", "cso", "pbp", "m3u", "rvz", "wbfs", "gcm",
                                       "zip", "7z", "gen", "md", "sms", "gg", "pce", "a26", "a78"]
        let candidates = tokens.compactMap { token -> String? in
            let path = token.hasPrefix("--") ? String(token.split(separator: "=", maxSplits: 1).last ?? "") : token
            guard path.hasPrefix("/home/deck/") || path.hasPrefix("/run/media/"),
                  path.contains("/Emulation/roms/"),
                  !path.contains("$"), !path.contains("`"),
                  !path.split(separator: "/").contains(".."),
                  extensions.contains((path as NSString).pathExtension.lowercased()) else { return nil }
            return path
        }
        // Multi-ROM commands need explicit matching; do not choose one arbitrarily.
        return candidates.count == 1 ? candidates[0] : nil
    }
}

private indirect enum BinaryShortcutValue {
    case object([String: BinaryShortcutValue]), string(String), integer(UInt32), ignored
}

/// Steam's binary KeyValues subset. Bounds and duplicate checks apply at every depth.
private struct BinaryShortcutReader {
    let bytes: [UInt8]
    var offset = 0
    var entries = 0
    var isFinished: Bool { offset == bytes.count }

    mutating func object(depth: Int) throws -> [String: BinaryShortcutValue] {
        guard depth <= 32 else { throw SteamShortcutImportError.malformed }
        var values: [String: BinaryShortcutValue] = [:]
        while true {
            let type = try take(1).first!
            if type == 8 { return values }
            let key = try string().lowercased()
            entries += 1
            guard entries <= 100_000, values[key] == nil else { throw SteamShortcutImportError.malformed }
            switch type {
            case 0: values[key] = .object(try object(depth: depth + 1))
            case 1: values[key] = .string(try string())
            case 2:
                let value = try take(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
                values[key] = .integer(value)
            case 3, 4, 6: _ = try take(4); values[key] = .ignored
            case 7, 10: _ = try take(8); values[key] = .ignored
            default: throw SteamShortcutImportError.unsupportedType
            }
        }
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= bytes.count - offset else { throw SteamShortcutImportError.malformed }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    mutating func string() throws -> String {
        let start = offset
        while offset < bytes.count && bytes[offset] != 0 {
            offset += 1
            guard offset - start <= 65_536 else { throw SteamShortcutImportError.malformed }
        }
        guard offset < bytes.count, let result = String(bytes: bytes[start..<offset], encoding: .utf8) else {
            throw SteamShortcutImportError.malformed
        }
        offset += 1
        return result
    }
}
