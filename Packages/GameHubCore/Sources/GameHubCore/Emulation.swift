import Foundation
import CryptoKit

public enum EmulatorKind: String, Codable, CaseIterable, Sendable {
    case retroArch, duckStation, pcsx2, rpcs3, dolphin
    public var displayName: String {
        switch self {
        case .retroArch: "RetroArch"
        case .duckStation: "DuckStation"
        case .pcsx2: "PCSX2"
        case .rpcs3: "RPCS3"
        case .dolphin: "Dolphin (GameCube / Wii)"
        }
    }
}
public enum DolphinGraphicsPreset: String, Codable, CaseIterable, Sendable {
    case emulatorSettings, metalNative, metal1080
    public var displayName: String {
        switch self {
        case .emulatorSettings: "Use Dolphin settings"
        case .metalNative: "Metal · native resolution"
        case .metal1080: "Metal · 3× resolution (about 1080p)"
        }
    }
    public var arguments: [String] {
        switch self {
        case .emulatorSettings: []
        case .metalNative: ["-v", "Metal", "-C", "Graphics.Settings.InternalResolution=1"]
        case .metal1080: ["-v", "Metal", "-C", "Graphics.Settings.InternalResolution=3"]
        }
    }
}

/// Reads app metadata without executing a program or importing an emulator's settings.
public struct EmulatorApplicationInfo: Equatable, Sendable {
    public let version: String
    public let bundleIdentifier: String
    public static func inspect(application: URL) throws -> Self {
        do { return try read(application: application) } catch { throw ROMError.emulatorMissing }
    }
    private static func read(application: URL) throws -> Self {
        guard application.isFileURL, application.pathExtension.lowercased() == "app" else { throw ROMError.emulatorMissing }
        let root = application.resolvingSymlinksInPath()
        let plist = root.appendingPathComponent("Contents/Info.plist").resolvingSymlinksInPath()
        guard plist.path.hasPrefix(root.path + "/") else { throw ROMError.emulatorMissing }
        let handle = try FileHandle(forReadingFrom: plist)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              !executable.contains("/"), !executable.contains("\\"), !executable.contains("\0"),
              executable != ".", executable != ".." else { throw ROMError.emulatorMissing }
        let binary = root.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).resolvingSymlinksInPath()
        guard binary.path.hasPrefix(root.path + "/Contents/MacOS/"),
              (try binary.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true,
              FileManager.default.isExecutableFile(atPath: binary.path) else { throw ROMError.emulatorMissing }
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? "Unknown version"
        return Self(version: String(version.prefix(128)), bundleIdentifier: String((info["CFBundleIdentifier"] as? String ?? "").prefix(256)))
    }
}
public enum EmulatorCommand {
    public static func arguments(kind: EmulatorKind, content: URL, core: URL? = nil, dolphinPreset: DolphinGraphicsPreset = .emulatorSettings) throws -> [String] {
        guard content.isFileURL, content.path.hasPrefix("/"), !content.path.contains("\0") else { throw ROMError.invalid }
        switch kind {
        case .retroArch:
            guard let core, core.isFileURL else { throw ROMError.coreMissing }
            return ["-f", "-L", core.path, content.path]
        case .duckStation, .pcsx2: return ["-batch", "-fullscreen", "--", content.path]
        case .rpcs3: return [content.path]
        case .dolphin:
            return ["-b", "-C", "Dolphin.Display.Fullscreen=True"] + dolphinPreset.arguments + ["-e", content.path]
        }
    }
}
public enum ROMError: LocalizedError {
    case invalid, coreMissing, missingPart, emulatorMissing
    public var errorDescription: String? {
        switch self {
        case .emulatorMissing: "The emulator application is missing or incomplete. Select an installed macOS emulator. Use the emulator’s own settings to configure required BIOS or firmware."
        case .invalid: "Unsupported or unsafe ROM descriptor. Keep all disc parts inside the selected folder."
        case .coreMissing: "Select an installed RetroArch core for this system."
        case .missingPart: "A disc image referenced by this game is missing. Copy every disc part before playing."
        }
    }
}
public struct ROMEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let relativePath: String
}
public struct ROMIndex: Codable, Sendable {
    public struct Cached: Codable, Sendable {
        public let signatures: [String: String]
        public let fingerprint: String
    }
    public var cache: [String: Cached] = [:]
    public var entries: [ROMEntry] = []
    public init() {}
    public mutating func scan(root: URL, system: String) throws {
        guard CompatibilityProfile.safeID(system) else { throw ROMError.invalid }
        let files = FileManager.default
        let root = root.resolvingSymlinksInPath()
        guard let iterator = files.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw ROMError.invalid }
        var candidates: [URL] = []
        var visited = 0
        while let url = iterator.nextObject() as? URL {
            visited += 1
            if visited > 100000 { break }
            if candidates.count >= 20000 || iterator.level > 12 { iterator.skipDescendants(); continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            if ["nes", "sfc", "smc", "gb", "gbc", "gba", "n64", "z64", "v64", "pbp", "gen", "md", "smd", "32x", "iso", "chd", "cue", "gdi", "m3u", "gcm", "rvz", "wia", "wbfs", "ciso"].contains(url.pathExtension.lowercased()) || url.lastPathComponent.uppercased() == "EBOOT.BIN" { candidates.append(url.resolvingSymlinksInPath()) }
        }
        var suppressed: Set<String> = []
        for descriptor in candidates where ["cue", "gdi", "m3u"].contains(descriptor.pathExtension.lowercased()) {
            for part in try Self.parts(of: descriptor, root: root) where part.path != descriptor.resolvingSymlinksInPath().path { suppressed.insert(part.path) }
        }
        var result: [String: ROMEntry] = [:]
        var nextCache: [String: Cached] = [:]
        for url in candidates.sorted(by: { $0.path < $1.path }) where !suppressed.contains(url.resolvingSymlinksInPath().path) {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let parts = try Self.parts(of: url, root: root)
            var signatures: [String: String] = [:]
            for part in parts {
                let values = try part.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                signatures[String(part.path.dropFirst(root.path.count + 1))] = "\(values.fileSize ?? -1):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }
            let fingerprint: String
            if let old = cache[relative], old.signatures == signatures { fingerprint = old.fingerprint } else {
                var digest = SHA256()
                // Descriptor names are not identity: hash each ordered payload digest, including disc order.
                let payloads = parts.filter { !["cue", "gdi", "m3u"].contains($0.pathExtension.lowercased()) }
                guard !payloads.isEmpty else { throw ROMError.missingPart }
                for descriptor in parts where descriptor.pathExtension.lowercased() == "cue" {
                    let text = try String(contentsOf: descriptor, encoding: .utf8)
                    let layout = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.uppercased().hasPrefix("FILE ") }.joined(separator: "\n")
                    digest.update(data: Data(SHA256.hash(data: Data(layout.utf8))))
                }
                for descriptor in parts where descriptor.pathExtension.lowercased() == "gdi" {
                    let handle = try FileHandle(forReadingFrom: descriptor)
                    defer { try? handle.close() }
                    let layout = try Self.gdiTracks(handle.read(upToCount: 16384) ?? Data()).map { $0.layout }.joined(separator: "\n")
                    digest.update(data: Data(SHA256.hash(data: Data(layout.utf8))))
                }
                for part in payloads {
                    let handle = try FileHandle(forReadingFrom: part)
                    defer { try? handle.close() }
                    var partDigest = SHA256()
                    while let data = try handle.read(upToCount: 1048576), !data.isEmpty { partDigest.update(data: data) }
                    digest.update(data: Data(partDigest.finalize()))
                }
                fingerprint = digest.finalize().map { String(format: "%02x", $0) }.joined()
            }
            nextCache[relative] = Cached(signatures: signatures, fingerprint: fingerprint)
            let id = "emulator:" + system + ":" + fingerprint
            result[id] = ROMEntry(id: id, title: url.deletingPathExtension().lastPathComponent, relativePath: relative)
        }
        cache = nextCache; entries = result.values.sorted { $0.title < $1.title }
    }
    private static func gdiTracks(_ data: Data) throws -> [(filename: String, layout: String)] {
        guard data.count < 16384, let text = String(data: data, encoding: .utf8) else { throw ROMError.invalid }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first, let count = Int(first), (3...99).contains(count), lines.count == count + 1 else { throw ROMError.invalid }
        let pattern = #"^(\d+)\s+(\d+)\s+(0|4)\s+(2048|2352)\s+(?:"([^"]+)"|([^\s"]+))\s+(\d+)$"#
        let expression = try NSRegularExpression(pattern: pattern)
        var tracks: [(filename: String, layout: String)] = []
        for (index, line) in lines.dropFirst().enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range) else { throw ROMError.invalid }
            func field(_ number: Int) -> String {
                guard let range = Range(match.range(at: number), in: line) else { return "" }
                return String(line[range])
            }
            guard Int(field(1)) == index + 1,
                  let sector = UInt32(field(2)), let offset = UInt32(field(7)), offset <= Int32.max,
                  index != 0 || field(3) == "4", index != 1 || field(3) == "0",
                  index != 2 || (field(3) == "4" && sector == 45000) else { throw ROMError.invalid }
            let name = field(5).isEmpty ? field(6) : field(5)
            guard ["bin", "raw"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else { throw ROMError.invalid }
            tracks.append((name, "\(index + 1) \(sector) \(field(3)) \(field(4)) \(offset)"))
        }
        return tracks
    }
    public static func parts(of file: URL, root: URL, depth: Int = 0) throws -> [URL] {
        let file = file.resolvingSymlinksInPath(), root = root.resolvingSymlinksInPath()
        guard depth < 8, file.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: file.path) else { throw ROMError.missingPart }
        guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw ROMError.invalid }
        let ext = file.pathExtension.lowercased()
        guard ["cue", "gdi", "m3u"].contains(ext) else { return [file] }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: 65537) ?? Data()
        guard data.count <= 65536, let text = String(data: data, encoding: .utf8) else { throw ROMError.invalid }
        var references: [String] = []
        if ext == "gdi" { references = try gdiTracks(data).map { $0.filename } }
        for raw in text.components(separatedBy: .newlines) {
            if ext == "gdi" { break }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if ext == "m3u" { references.append(line); continue }
            guard line.uppercased().hasPrefix("FILE ") else { continue }
            let tail = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if tail.hasPrefix("\""), let end = tail.dropFirst().firstIndex(of: "\"") { references.append(String(tail[tail.index(after: tail.startIndex)..<end])) } else if let first = tail.split(separator: " ").first { references.append(String(first)) }
        }
        guard !references.isEmpty, references.count <= 100 else { throw ROMError.invalid }
        var result = [file]
        for reference in references {
            guard !reference.hasPrefix("/"), !reference.contains(":"), !reference.contains("\\") else { throw ROMError.invalid }
            result += try parts(of: file.deletingLastPathComponent().appendingPathComponent(reference), root: root, depth: depth + 1)
        }
        return result
    }
}
