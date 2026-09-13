import Foundation
import AppKit

@MainActor enum GameHubRuntime {
    static let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GameHub")
    static var profiles: CompatibilityProfileStore { .init(directory: support.appendingPathComponent("Profiles")) }
    struct Binding: Codable, Sendable {
        let runtime: Data
        let prefix: Data
        let renderer: Data
        let hashes: [String: String]
    }
    struct Locations: Sendable {
        let runtime: URL
        let prefix: URL
        let renderer: URL
        var steam: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe") }
    }
    enum RuntimeError: LocalizedError {
        case unconfigured, access, changed, missing
        var errorDescription: String? {
            switch self {
            case .unconfigured: "This game needs a compatibility profile. Open Launch Settings to select one."
            case .access: "A saved folder permission is stale. Reconnect the runtime folders in Launch Settings."
            case .changed: "The pinned runtime has changed. Restore its verified files or test a separate runtime before using this profile."
            case .missing: "The Windows Steam runtime or game files are unavailable. Check that their drive is connected."
            }
        }
    }
    static func binding(_ id: String) throws -> Binding {
        guard CompatibilityProfile.safeID(id) else { throw RuntimeError.unconfigured }
        return try JSONDecoder().decode(Binding.self, from: Data(contentsOf: support.appendingPathComponent("RuntimeBindings/" + id + ".json")))
    }
    static func locations(_ binding: Binding) throws -> Locations {
        func resolve(_ data: Data) throws -> URL {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
            guard !stale else { throw RuntimeError.access }
            return url
        }
        return try .init(runtime: resolve(binding.runtime), prefix: resolve(binding.prefix), renderer: resolve(binding.renderer))
    }
    static func configuredProfiles() -> [String: String] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: profiles.directory, includingPropertiesForKeys: nil)) ?? []
        var result: [String: String] = [:]
        for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" && !file.lastPathComponent.contains(".previous.") {
            guard let profile = try? profiles.load(file.deletingPathExtension().lastPathComponent),
                  profile.validation == "owner-accepted", (try? binding(profile.runtimeID)) != nil else { continue }
            result[String(profile.gameID.dropFirst(6))] = profile.profileID
        }
        if let data = try? Data(contentsOf: support.appendingPathComponent("active-profiles.json")),
           let overrides = try? JSONDecoder().decode([String: String].self, from: data) {
            for (appID, id) in overrides {
                guard let profile = try? profiles.load(id), profile.gameID == "steam:" + appID,
                      (try? binding(profile.runtimeID)) != nil else { continue }
                result[appID] = id
            }
        }
        return result
    }
    static func activate(_ profile: CompatibilityProfile) throws {
        try profile.validate()
        _ = try binding(profile.runtimeID)
        let file = support.appendingPathComponent("active-profiles.json")
        var overrides = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
        overrides[String(profile.gameID.dropFirst(6))] = profile.profileID
        try JSONEncoder().encode(overrides).write(to: file, options: .atomic)
    }
    static func windowsDiscovery() async -> ProviderDiscovery {
        let ids = configuredProfiles()
        var records: [GameRecord] = []
        var diagnostics: [String] = []
        var roots: Set<URL> = []
        for id in Set(ids.values) {
            guard let profile = try? profiles.load(id), let binding = try? binding(profile.runtimeID), let paths = try? locations(binding) else { continue }
            let root = paths.steam.deletingLastPathComponent()
            guard roots.insert(root).inserted else { continue }
            let access = paths.prefix.startAccessingSecurityScopedResource()
            let result = await Task.detached(priority: .utility) { SteamWindowsProvider(steamRoot: root, profileIDs: ids, driveRoots: ["c": paths.prefix.appendingPathComponent("drive_c")]).scan() }.value
            if access { paths.prefix.stopAccessingSecurityScopedResource() }
            records += result.records.map { record in
                GameRecord(id: record.id, title: record.title, launchTargets: record.launchTargets.map { target in
                    var target = target
                    target.verified = target.profileID.flatMap { try? profiles.load($0).validation } == "owner-accepted"
                    return target
                }, artwork: record.artwork)
            }
            diagnostics += result.diagnostics
        }
        return .init(records: records, diagnostics: diagnostics)
    }
    static func launch(appID: String, profileID: String) async throws {
        let profile = try profiles.load(profileID)
        guard profile.gameID == "steam:" + appID else { throw RuntimeError.unconfigured }
        let pin = try binding(profile.runtimeID)
        let paths = try locations(pin)
        let urls = [paths.runtime, paths.prefix, paths.renderer]
        let access = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (index, url) in urls.enumerated() where access[index] { url.stopAccessingSecurityScopedResource() } }
        try await Task.detached(priority: .userInitiated) {
            guard !pin.hashes.isEmpty else { throw RuntimeError.changed }
            for (relative, hash) in pin.hashes {
                let components = relative.split(separator: "/", omittingEmptySubsequences: false)
                guard components.count > 1, !components.contains(".."), !components.contains(""),
                      ["runtime", "renderer"].contains(components[0]) else { throw RuntimeError.changed }
                let root = components[0] == "runtime" ? paths.runtime : paths.renderer
                let file = root.appendingPathComponent(components.dropFirst().joined(separator: "/")).resolvingSymlinksInPath()
                guard file.path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw RuntimeError.changed }
                do { try EngineArtifactVerifier.verify(file: file, expectedSHA256: hash) } catch { throw RuntimeError.changed }
            }
        }.value
        guard FileManager.default.fileExists(atPath: paths.steam.path),
              SteamWindowsProvider(steamRoot: paths.steam.deletingLastPathComponent(), profileIDs: [appID: profileID], driveRoots: ["c": paths.prefix.appendingPathComponent("drive_c")]).scan().records.contains(where: { $0.id.externalID == appID }) else { throw RuntimeError.missing }
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = paths.prefix.path
        environment["WINEDEBUG"] = "-all,err+all"
        environment["PATH"] = paths.runtime.appendingPathComponent("bin").path + ":/usr/bin:/bin"
        environment["WINEDLLPATH"] = paths.renderer.appendingPathComponent("wine").path + ":" + paths.runtime.appendingPathComponent("lib/wine").path
        environment["WINEDLLPATH_PREPEND"] = paths.renderer.appendingPathComponent("wine").path
        environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = paths.renderer.appendingPathComponent("external/libd3dshared.dylib").path
        environment["WINEDLLOVERRIDES"] = "d3d11,d3d12,dxgi=b"
        for (key, value) in profile.environment { environment[key] = value }
        let process = Process()
        process.executableURL = paths.runtime.appendingPathComponent("bin/wine")
        process.arguments = [paths.steam.path, "-applaunch", appID] + profile.arguments
        process.environment = environment
        process.currentDirectoryURL = paths.steam.deletingLastPathComponent()
        // Raw Wine output can contain account paths. Keep it out of exported app diagnostics.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
