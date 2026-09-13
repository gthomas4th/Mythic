import Foundation

/// Reads installed manifests only. Steam continues to own authentication and all content operations.
public struct SteamWindowsProvider: GameProvider {
    public let id: ProviderID = .steam
    public let steamRoot: URL
    public let profileIDs: [String: String]
    public let driveRoots: [String: URL]
    public init(steamRoot: URL, profileIDs: [String: String] = [:], driveRoots: [String: URL] = [:]) {
        self.steamRoot = steamRoot; self.profileIDs = profileIDs
        self.driveRoots = driveRoots.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
    }
    public func discoverInstalled() async -> ProviderDiscovery { scan() }
    public func scan() -> ProviderDiscovery {
        let files = FileManager.default
        var records: [GameRecord] = []
        var diagnostics: [String] = []
        var roots = [steamRoot.resolvingSymlinksInPath()]
        let folders = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if files.fileExists(atPath: folders.path) {
            do {
                guard let object = try ValveKeyValues.parse(read(folders)).object("libraryfolders") else {
                    throw ValveKeyValues.ParseError.malformed
                }
                let libraries = object.entries.filter { UInt($0.key) != nil }
                guard libraries.count <= 256 else { throw ValveKeyValues.ParseError.limitExceeded }
                for entry in libraries {
                    let path: String?
                    switch entry.value {
                    case .string(let value): path = value
                    case .object(let value): path = try value.string("path")
                    }
                    guard let path, let root = mappedLibrary(path) else {
                        diagnostics.append("windows-steam.library-unmapped-or-invalid"); continue
                    }
                    if !roots.contains(root) { roots.append(root) }
                }
            } catch { diagnostics.append("windows-steam.library-list-invalid") }
        }
        for root in roots {
            let apps = root.appendingPathComponent("steamapps")
            guard let entries = try? files.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil) else {
                diagnostics.append("windows-steam.library-unavailable"); continue
            }
            for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                do {
                    let manifest = try SteamManifest(text: read(file), libraryRoot: root)
                    guard file.lastPathComponent == "appmanifest_\(manifest.appID).acf", manifest.stateFlags == 4,
                          manifest.appID != "228980", let locator = SteamLaunch.url(appID: manifest.appID) else { continue }
                    let common = apps.appendingPathComponent("common").resolvingSymlinksInPath()
                    let payload = common.appendingPathComponent(manifest.installDirectory).resolvingSymlinksInPath()
                    var directory: ObjCBool = false
                    guard payload.path.hasPrefix(common.path + "/"), files.fileExists(atPath: payload.path, isDirectory: &directory), directory.boolValue else { continue }
                    guard !records.contains(where: { $0.id.externalID == manifest.appID }) else { continue }
                    let profile = profileIDs[manifest.appID]
                    let target = LaunchTarget(id: "steam:\(manifest.appID):windows", kind: .wineSteam,
                        locator: locator, application: payload, available: profile != nil, verified: profile != nil, profileID: profile)
                    records.append(.init(id: .init(provider: .steam, externalID: manifest.appID), title: manifest.title,
                        launchTargets: [target], artwork: SteamNativeProvider.cachedArtwork(appID: manifest.appID, steamRoot: steamRoot)))
                } catch { diagnostics.append("windows-steam.manifest-invalid") }
            }
        }
        return .init(records: LaunchResolver.merge(records), diagnostics: diagnostics)
    }
    private func mappedLibrary(_ path: String) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let prefix = Array(normalized.prefix(3))
        guard prefix.count == 3, prefix[1] == ":", prefix[2] == "/",
              let root = driveRoots[String(prefix[0]).lowercased()]?.resolvingSymlinksInPath() else { return nil }
        let parts = normalized.dropFirst(3).split(separator: "/")
        guard !parts.contains(where: { $0 == "." || $0 == ".." || $0.contains(":") || $0.contains("\0") }) else { return nil }
        let result = parts.reduce(root) { $0.appendingPathComponent(String($1)) }.resolvingSymlinksInPath()
        guard result == root || result.path.hasPrefix(root.path + "/") else { return nil }
        return result
    }
    private func read(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw ValveKeyValues.ParseError.limitExceeded
        }
        return text
    }
}
