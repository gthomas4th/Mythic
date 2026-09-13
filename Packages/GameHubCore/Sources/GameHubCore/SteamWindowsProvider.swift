import Foundation

/// Reads installed manifests only. Steam continues to own authentication and all content operations.
public struct SteamWindowsProvider: GameProvider {
    public let id: ProviderID = .steam
    public let steamRoot: URL
    public let profileIDs: [String: String]
    public init(steamRoot: URL, profileIDs: [String: String] = [:]) {
        self.steamRoot = steamRoot; self.profileIDs = profileIDs
    }
    public func discoverInstalled() async -> ProviderDiscovery { scan() }
    public func scan() -> ProviderDiscovery {
        let files = FileManager.default
        let apps = steamRoot.appendingPathComponent("steamapps")
        guard let entries = try? files.contentsOfDirectory(at: apps, includingPropertiesForKeys: nil) else {
            return .init(records: [], diagnostics: ["windows-steam.library-unavailable"])
        }
        var records: [GameRecord] = []
        var diagnostics: [String] = []
        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
            do {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
                guard data.count <= 8 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw ValveKeyValues.ParseError.limitExceeded }
                let manifest = try SteamManifest(text: text, libraryRoot: steamRoot)
                guard file.lastPathComponent == "appmanifest_\(manifest.appID).acf", manifest.stateFlags == 4,
                      manifest.appID != "228980", let locator = SteamLaunch.url(appID: manifest.appID) else { continue }
                let common = apps.appendingPathComponent("common").resolvingSymlinksInPath()
                let payload = common.appendingPathComponent(manifest.installDirectory).resolvingSymlinksInPath()
                var directory: ObjCBool = false
                guard payload.path.hasPrefix(common.path + "/"), files.fileExists(atPath: payload.path, isDirectory: &directory), directory.boolValue else { continue }
                let profile = profileIDs[manifest.appID]
                let target = LaunchTarget(id: "steam:\(manifest.appID):windows", kind: .wineSteam,
                    locator: locator, application: payload, available: profile != nil, verified: profile != nil, profileID: profile)
                let image = steamRoot.appendingPathComponent("appcache/librarycache/\(manifest.appID)_library_600x900.jpg")
                records.append(.init(id: .init(provider: .steam, externalID: manifest.appID), title: manifest.title,
                    launchTargets: [target], artwork: files.fileExists(atPath: image.path) ? image : nil))
            } catch { diagnostics.append("windows-steam.manifest-invalid") }
        }
        return .init(records: LaunchResolver.merge(records), diagnostics: diagnostics)
    }
}
