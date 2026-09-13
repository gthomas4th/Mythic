import Foundation

public struct SteamManifest: Sendable {
    public let appID: String
    public let title: String
    public let installDirectory: String
    public let stateFlags: UInt64
    public let lastUpdated: UInt64
    public let libraryRoot: URL
    public init(text: String, libraryRoot: URL) throws {
        guard let state = try ValveKeyValues.parse(text).object("AppState"),
              let appID = try state.string("appid"), SteamLaunch.url(appID: appID) != nil,
              let title = try state.string("name"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let directory = try state.string("installdir"), !directory.isEmpty,
              directory != ".", directory != "..", !directory.contains("/"), !directory.contains("\\"),
              let flags = try state.string("StateFlags").flatMap(UInt64.init),
              let updated = try state.string("LastUpdated").flatMap(UInt64.init)
        else { throw ValveKeyValues.ParseError.malformed }
        self.appID = appID; self.title = title; self.installDirectory = directory
        self.stateFlags = flags; self.lastUpdated = updated; self.libraryRoot = libraryRoot
    }
}
public struct SteamDiscoveryResult: Sendable {
    public let records: [GameRecord]
    public let manifests: [SteamManifest]
    /// Only codes and app IDs; no account names or private filesystem paths.
    public let diagnostics: [String]
}
public struct SteamNativeProvider: GameProvider {
    public let id: ProviderID = .steam
    public let steamRoot: URL
    public init(steamRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Steam")) { self.steamRoot = steamRoot }
    public func discoverInstalled() async -> ProviderDiscovery {
        let result = scan()
        return .init(records: result.records, diagnostics: result.diagnostics)
    }
    public func scan() -> SteamDiscoveryResult {
        let files = FileManager.default
        var diagnostics: [String] = []
        var roots = [steamRoot.standardizedFileURL.resolvingSymlinksInPath()]
        let folders = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if files.fileExists(atPath: folders.path) {
            do {
                guard let object = try ValveKeyValues.parse(readManifest(folders)).object("libraryfolders")
                else { throw ValveKeyValues.ParseError.malformed }
                for entry in object.entries where UInt(entry.key) != nil {
                    let path: String?
                    switch entry.value {
                    case .string(let text): path = text
                    case .object(let value): path = try value.string("path")
                    }
                    guard let path, path.hasPrefix("/") else {
                        diagnostics.append("library.invalid-path"); continue
                    }
                    let root = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
                    if !roots.contains(root) { roots.append(root) }
                }
            } catch { diagnostics.append("library.unreadable-or-malformed") }
        }
        var records: [String: GameRecord] = [:]
        var manifests: [SteamManifest] = []
        for root in roots {
            let apps = root.appendingPathComponent("steamapps")
            let entries: [URL]
            do { entries = try files.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil) } catch { diagnostics.append("library.unavailable"); continue }
            for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                do {
                    let manifest = try SteamManifest(text: readManifest(file), libraryRoot: root)
                    guard file.lastPathComponent == "appmanifest_\(manifest.appID).acf" else {
                        diagnostics.append("manifest.identity-mismatch"); continue
                    }
                    manifests.append(manifest)
                    guard manifest.stateFlags == 4 else {
                        diagnostics.append("steam:\(manifest.appID).not-fully-installed"); continue
                    }
                    let common = apps.appendingPathComponent("common").resolvingSymlinksInPath()
                    let payload = common.appendingPathComponent(manifest.installDirectory).resolvingSymlinksInPath()
                    guard payload.path.hasPrefix(common.path + "/"),
                          let application = Self.nativeApplication(in: payload, expectedNames: [manifest.title, manifest.installDirectory]) else {
                        diagnostics.append("steam:\(manifest.appID).native-payload-unverified"); continue
                    }
                    guard records[manifest.appID] == nil else {
                        diagnostics.append("steam:\(manifest.appID).duplicate"); continue
                    }
                    guard let locator = SteamLaunch.url(appID: manifest.appID) else { continue }
                    records[manifest.appID] = GameRecord(
                        id: .init(provider: .steam, externalID: manifest.appID), title: manifest.title,
                        launchTargets: [.init(id: "steam:\(manifest.appID):native", kind: .nativeMac,
                                              locator: locator, application: application)],
                        artwork: Self.cachedArtwork(appID: manifest.appID, steamRoot: steamRoot))
                } catch { diagnostics.append("manifest.unreadable-or-malformed") }
            }
        }
        return .init(records: records.values.sorted { $0.id.externalID < $1.id.externalID },
                     manifests: manifests, diagnostics: diagnostics)
    }
    private func readManifest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8)
        else { throw ValveKeyValues.ParseError.limitExceeded }
        return text
    }
    public static func cachedArtwork(appID: String, steamRoot: URL) -> URL? {
        guard SteamLaunch.url(appID: appID) != nil else { return nil }
        let cache = steamRoot.appendingPathComponent("appcache/librarycache").resolvingSymlinksInPath()
        let names = ["\(appID)/library_600x900.jpg", "\(appID)/library_600x900_2x.jpg",
                     "\(appID)_library_600x900.jpg", "\(appID)_library_600x900_2x.jpg"]
        for name in names {
            let file = cache.appendingPathComponent(name).resolvingSymlinksInPath()
            guard file.path.hasPrefix(cache.path + "/"),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else { continue }
            return file
        }
        return nil
    }
    /// Read-only evidence check. Unknown layouts remain unverified, never guessed native.
    public static func nativeApplication(in root: URL, expectedNames: [String]? = nil) -> URL? {
        func normalized(_ name: String) -> String {
            String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let names = (expectedNames ?? [root.deletingPathExtension().lastPathComponent]).map(normalized)
        let files = FileManager.default
        guard let iterator = files.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                               options: [.skipsHiddenFiles]) else { return nil }
        var candidates: [URL] = root.pathExtension == "app" ? [root] : []
        var visited = 0
        while let file = iterator.nextObject() as? URL {
            visited += 1
            if visited > 20_000 { break }
            if iterator.level > 6 { iterator.skipDescendants(); continue }
            if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                iterator.skipDescendants(); continue
            }
            if file.pathExtension == "app" { candidates.append(file); iterator.skipDescendants() }
        }
        for application in candidates.sorted(by: { $0.path < $1.path }) {
            guard names.contains(normalized(application.deletingPathExtension().lastPathComponent)) else { continue }
            let info = application.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: info),
                  let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  dict["CFBundlePackageType"] as? String == "APPL",
                  let name = dict["CFBundleExecutable"] as? String, !name.isEmpty,
                  !name.contains("/"), name != ".", name != ".." else { continue }
            if let platforms = dict["CFBundleSupportedPlatforms"] as? [String], !platforms.contains("MacOSX") { continue }
            let binary = application.appendingPathComponent("Contents/MacOS/\(name)").resolvingSymlinksInPath()
            guard binary.path.hasPrefix(application.resolvingSymlinksInPath().path + "/"),
                  files.isExecutableFile(atPath: binary.path),
                  let handle = try? FileHandle(forReadingFrom: binary) else { continue }
            let header = try? handle.read(upToCount: 4096)
            try? handle.close()
            // 64-bit Mach-O arm64/x86_64 only. Universal binaries checked below.
            if let header, header.count >= 8 {
                let bytes = Array(header)
                if Array(bytes[0..<4]) == [0xcf, 0xfa, 0xed, 0xfe],
                   [UInt8(7), UInt8(12)].contains(bytes[4]), Array(bytes[5..<8]) == [0, 0, 1] { return application }
                // Universal (big-endian fat32/fat64) headers list every contained CPU.
                let magic = Array(bytes[0..<4])
                if magic == [0xca, 0xfe, 0xba, 0xbe] || magic == [0xca, 0xfe, 0xba, 0xbf] {
                    let count = bytes[4..<8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    let stride = magic.last == 0xbf ? 32 : 20
                    guard count > 0, count <= 64, bytes.count >= 8 + Int(count) * stride else { continue }
                    for architecture in 0..<Int(count) {
                        let offset = 8 + architecture * stride
                        let cpu = Array(bytes[offset..<(offset + 4)])
                        if cpu == [1, 0, 0, 7] || cpu == [1, 0, 0, 12] { return application }
                    }
                }
            }
        }
        return nil
    }
}
