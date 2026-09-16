//
//  GameDataStore.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 2/12/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import OSLog

// SQLite is authoritative; the original defaults blob remains a recovery source.
@Observable @MainActor final class GameDataStore {
    static let shared: GameDataStore = .init()
    let log: Logger = .custom(category: "GameDataStore")
    
    private var catalog: CatalogStore?
    private(set) var persistenceError: String?
    private var persistenceReady = false
    private var firstSeenDates: [String: Date] = [:]
    private var preferenceCache: [String: CatalogStore.Preference] = [:]
    
    var library: Set<Game> = [] {
        didSet {
            libraryGeneration &+= 1
            displayLibraryCache = nil
            if persistenceReady { persistLibrary() }
        }
    }
    @ObservationIgnored private var libraryGeneration = 0
    @ObservationIgnored private var discoveredGeneration = 0
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var displayLibraryCache: Set<Game>?
    @ObservationIgnored private var displayLibraryVersion: DisplayLibraryVersion?

    private struct DisplayLibraryVersion: Equatable {
        let library: Int
        let discovered: Int
        let connections: Int
        let roms: Int
    }

    @MainActor private init() {
        do {
            let folder = GameHubRuntime.support.appendingPathComponent("Catalog")
            catalog = try CatalogStore(url: folder.appendingPathComponent("catalog.sqlite"))
            if let saved = try catalog?.importedGameDetails() {
                library = Set(try saved.values.map { try PropertyListDecoder().decode(AnyGame.self, from: $0).base })
            } else {
                let old = UserDefaults.standard.data(forKey: "games")
                let legacy = try old.map { try PropertyListDecoder().decode([AnyGame].self, from: $0) } ?? []
                let backup = folder.appendingPathComponent("legacy-games-before-import.plist")
                if let old, !FileManager.default.fileExists(atPath: backup.path) { try old.write(to: backup, options: .atomic) }
                library = Set(legacy.map(\.base))
                try catalog?.importGameDetailsOnce(encodedLibrary())
            }
            persistenceReady = true
            importLegacyCatalog()
            preferenceCache = (try? catalog?.preferences()) ?? [:]
            restorePreferences(for: Array(library))
        } catch {
            persistenceError = "The catalog could not be opened. Original data and backups have been preserved; changes will not be saved."
            if library.isEmpty, let data = UserDefaults.standard.data(forKey: "games"), let legacy = try? PropertyListDecoder().decode([AnyGame].self, from: data) {
                library = Set(legacy.map(\.base))
            }
        }
        if let cached = try? catalog?.records() {
            discoveredGames = Set(cached.filter { $0.id.provider == .steam }.compactMap { record in
                guard let target = record.launchTargets.first else { return nil }
                let game = SteamGame(record: record, target: target)
                return game
            })
            restorePreferences(for: Array(discoveredGames))
        }
        connectionGames = ConnectionGame.libraryGames()
        restorePreferences(for: Array(connectionGames))
    }

    private func encodedLibrary() throws -> [String: Data] {
        var result: [String: Data] = [:]
        for game in library {
            result[identity(for: game)] = try PropertyListEncoder().encode(AnyGame(game))
        }
        return result
    }
    private func persistLibrary() {
        guard persistenceReady else { return }
        do {
            try catalog?.replaceGameDetails(encodedLibrary())
            importLegacyCatalog()
            for game in library { HubGameOptions.shared.apply(to: game) }
        } catch { persistenceError = "Library changes could not be saved. The previous catalog snapshot is preserved." }
    }

    private(set) var discoveredGames: Set<Game> = [] {
        didSet {
            discoveredGeneration &+= 1
            displayLibraryCache = nil
        }
    }
    private(set) var connectionGames: Set<Game> = [] {
        didSet {
            connectionGeneration &+= 1
            displayLibraryCache = nil
        }
    }
    private(set) var discoveryDiagnostics: [String] = []
    private var completeLibrary: Set<Game> { library.union(discoveredGames).union(ROMLibrary.shared.games).union(connectionGames) }
    var hacksAndHomebrewLibrary: Set<Game> {
        Set(completeLibrary.filter(ROMCatalogPolicy.isHacksOrHomebrew))
    }
    var displayLibrary: Set<Game> {
        let version = DisplayLibraryVersion(library: libraryGeneration, discovered: discoveredGeneration,
            connections: connectionGeneration, roms: ROMLibrary.shared.catalogGeneration)
        if version == displayLibraryVersion, let displayLibraryCache { return displayLibraryCache }
        let visible = completeLibrary.filter {
            !ROMCatalogPolicy.isHacksOrHomebrew($0)
                && !ROMCatalogPolicy.isHiddenWithoutArtwork($0)
                && !Self.isEpicAddOn($0)
        }
        var uniqueROMs: [String: ROMGame] = [:]
        var result = Set(visible.filter { !($0 is ROMGame) })
        for case let game as ROMGame in visible {
            let key = ROMCatalogPolicy.deduplicationKey(for: game)
            if let current = uniqueROMs[key] {
                if ROMCatalogPolicy.prefers(game, over: current) { uniqueROMs[key] = game }
            } else {
                uniqueROMs[key] = game
            }
        }
        result.formUnion(uniqueROMs.values.map { $0 as Game })
        displayLibraryVersion = version
        displayLibraryCache = result
        return result
    }

    func invalidateDisplayLibrary() {
        displayLibraryCache = nil
        displayLibraryVersion = nil
    }

    private static func isEpicAddOn(_ game: Game) -> Bool {
        guard game.storefront == .epicGames else { return false }
        let title = game.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return title.localizedCaseInsensitiveContains("fortnite")
            && title.localizedCaseInsensitiveContains("content")
    }

    var recent: Game? {
        guard !displayLibrary.allSatisfy({ $0.lastLaunched == nil }) else { return nil }

        return displayLibrary.max {
            $0.lastLaunched ?? .distantPast < $1.lastLaunched ?? .distantPast
        }
    }

    var recentlyAdded: [Game] {
        displayLibrary.filter { firstSeenDates[identity(for: $0)] != nil }.sorted {
            let left = firstSeenDates[identity(for: $0)] ?? .distantPast
            let right = firstSeenDates[identity(for: $1)] ?? .distantPast
            if left != right { return left > right }
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? identity(for: $0) < identity(for: $1) : order == .orderedAscending
        }
    }
    private func rememberFirstSeen(for game: Game) {
        guard persistenceReady, let catalog else { return }
        let id = identity(for: game)
        if let date = preferenceCache[id]?.firstSeen {
            firstSeenDates[id] = date
            return
        }
        do {
            let date = try catalog.recordFirstSeen(for: id)
            firstSeenDates[id] = date
            var preference = preferenceCache[id] ?? .init()
            preference.firstSeen = date
            preferenceCache[id] = preference
        } catch { persistenceError = "The date this game was added could not be saved." }
    }
    private func identity(for game: Game) -> String {
        if game is SteamGame || game is ROMGame { return game.id }
        return (game.storefront == .epicGames ? "epic:" : "local:") + game.id
    }
    private func importLegacyCatalog() {
        do {
            let folder = GameHubRuntime.support.appendingPathComponent("Catalog")
            let backup = folder.appendingPathComponent("legacy-games-before-import.plist")
            if !FileManager.default.fileExists(atPath: backup.path), let data = UserDefaults.standard.data(forKey: "games") {
                try data.write(to: backup, options: .atomic)
            }
            let existing = Set(try catalog?.records().map { $0.id.description } ?? [])
            let records = library.map { game in
                GameRecord(id: .init(provider: game.storefront == .epicGames ? .epic : .local, externalID: game.id),
                    title: game.title, launchTargets: [], artwork: game.verticalImageURL)
            }
            try catalog?.upsert(records)
            let saved = try catalog?.preferences() ?? [:]
            let imported = Dictionary(uniqueKeysWithValues: library.compactMap { game -> (String, CatalogStore.Preference)? in
                let id = identity(for: game)
                guard !existing.contains(id) else { return nil }
                return (id, .init(favorite: game.isFavourited, lastPlayed: game.lastLaunched,
                    preferredTargetID: nil, firstSeen: saved[id]?.firstSeen))
            })
            try catalog?.setPreferences(imported)
        } catch { persistenceError = "The existing library could not be imported. Its original data is preserved." }
    }
    func restorePreferences(for game: Game) {
        restorePreferences(for: [game])
    }
    func restorePreferences(for games: [Game]) {
        guard !games.isEmpty else { return }
        let observedAt = Date()
        var additions: [String: CatalogStore.Preference] = [:]
        for game in games {
            HubGameOptions.shared.apply(to: game)
            let id = identity(for: game)
            let saved: CatalogStore.Preference
            if let cached = preferenceCache[id] {
                saved = cached
            } else {
                saved = .init(firstSeen: observedAt)
                preferenceCache[id] = saved
                additions[id] = saved
            }
            firstSeenDates[id] = saved.firstSeen ?? observedAt
            game.isFavourited = saved.favorite
            game.lastLaunched = saved.lastPlayed
            if let steam = game as? SteamGame { steam.preferredTargetID = saved.preferredTargetID }
        }
        if !additions.isEmpty {
            do { try catalog?.insertPreferencesIfAbsent(additions) }
            catch { persistenceError = "New catalog entries could not be recorded. Existing preferences were preserved." }
        }
    }
    func savePreferences(for game: Game) {
        guard persistenceReady else { return }
        do {
            let id = identity(for: game)
            let preference = CatalogStore.Preference(favorite: game.isFavourited, lastPlayed: game.lastLaunched,
                preferredTargetID: (game as? SteamGame)?.preferredTargetID, firstSeen: firstSeenDates[id])
            try catalog?.setPreference(preference, for: id)
            preferenceCache[id] = preference
            if library.contains(game) { persistLibrary() }
        } catch { persistenceError = "Game preferences could not be saved." }
    }

    func refreshFromStorefronts(_ storefronts: Game.Storefront...) async throws {
        GameListViewModel.shared.isUpdatingLibrary = true
        defer {
            GameListViewModel.shared.isUpdatingLibrary = false
        }
        
        // if variadics are empty, default to all cases
        let storefronts = storefronts.isEmpty ? Game.Storefront.allCases : storefronts as [Game.Storefront]
        
        // Read-only discovery is separate from legacy persistence, and runs before Epic so
        // an Epic login/network failure cannot hide installed Steam titles.
        if storefronts.contains(.steam) {
            let result = await Task.detached(priority: .utility) {
                await SteamNativeProvider().discoverInstalled()
            }.value
            let windows = await GameHubRuntime.windowsDiscovery()
            let cached = ((try? catalog?.records()) ?? []).filter { $0.id.provider == .steam }.map { record in
                GameRecord(id: record.id, title: record.title, launchTargets: record.launchTargets.map { target in
                    var unavailable = target; unavailable.available = false; return unavailable
                }, artwork: record.artwork)
            }
            let records = HubConnections.shared.targets(for: LaunchResolver.merge(cached + result.records + windows.records))
            discoveryDiagnostics = result.diagnostics + windows.diagnostics
            if persistenceReady {
                do { try catalog?.upsert(records) } catch { persistenceError = "Library changes could not be saved." }
            }
            var refreshed: Set<Game> = []
            for record in records {
                guard let target = LaunchResolver.resolve(record.launchTargets) ?? record.launchTargets.first else { continue }
                let game = SteamGame(record: record, target: target)
                refreshed.insert(game)
            }
            discoveredGames = refreshed
            restorePreferences(for: Array(refreshed))
            for diagnostic in discoveryDiagnostics { log.notice("Steam discovery: \(diagnostic, privacy: .public)") }
        }

        // legendary (epic games)
        if storefronts.contains(.epicGames) {
            do {
                let installables = try Legendary.getInstallableGames()
                let installed = try Legendary.getInstalledGames()
                var refreshed = library
                
                // add installables that aren't installed
                for game in installables where !installed.contains(where: { $0 == game }) {
                    refreshed.update(with: game)
                }
                
                // installed: merge instead of overwrite
                for fetchedGame in installed {
                    if let existing = refreshed.first(where: { $0 == fetchedGame }) {
                        try existing.merge(with: fetchedGame, requiring: .identicalIgnoredKeys)
                        refreshed.update(with: existing)
                    } else {
                        refreshed.update(with: fetchedGame)
                    }
                }
                library = refreshed
                restorePreferences(for: Array(refreshed))
            } catch {
                log.error("Unable to refresh game data from Epic Games: \(error.localizedDescription)")
                throw error
            }
        }
        
        // TODO: others
        // if storefronts.contains(...) { ... }
    }
}
