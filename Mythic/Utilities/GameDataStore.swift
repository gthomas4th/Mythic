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
    
    var library: Set<Game> = [] {
        didSet { if persistenceReady { persistLibrary() } }
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
            for game in library { restorePreferences(for: game) }
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
                if let saved = try? catalog?.preference(for: game.id) {
                    game.isFavourited = saved.favorite; game.lastLaunched = saved.lastPlayed
                    game.preferredTargetID = saved.preferredTargetID
                }
                rememberFirstSeen(for: game)
                return game
            })
        }
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
            for game in library { HubGameOptions.shared.apply(to: game); rememberFirstSeen(for: game) }
        } catch { persistenceError = "Library changes could not be saved. The previous catalog snapshot is preserved." }
    }

    private(set) var discoveredGames: Set<Game> = []
    private(set) var discoveryDiagnostics: [String] = []
    var displayLibrary: Set<Game> { library.union(discoveredGames).union(ROMLibrary.shared.games) }

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
        do {
            firstSeenDates[identity(for: game)] = try catalog.recordFirstSeen(for: identity(for: game))
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
            for game in library {
                let record = GameRecord(id: .init(provider: game.storefront == .epicGames ? .epic : .local, externalID: game.id),
                    title: game.title, launchTargets: [], artwork: game.verticalImageURL)
                try catalog?.upsert([record])
                if !existing.contains(identity(for: game)) {
                    try catalog?.setPreference(.init(favorite: game.isFavourited, lastPlayed: game.lastLaunched), for: identity(for: game))
                }
            }
        } catch { persistenceError = "The existing library could not be imported. Its original data is preserved." }
    }
    func restorePreferences(for game: Game) {
        HubGameOptions.shared.apply(to: game)
        rememberFirstSeen(for: game)
        if let saved = try? catalog?.preference(for: identity(for: game)) {
            game.isFavourited = saved.favorite; game.lastLaunched = saved.lastPlayed
        }
    }
    func savePreferences(for game: Game) {
        guard persistenceReady else { return }
        do {
            try catalog?.setPreference(.init(favorite: game.isFavourited, lastPlayed: game.lastLaunched,
                preferredTargetID: (game as? SteamGame)?.preferredTargetID), for: identity(for: game))
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
                if let saved = try? catalog?.preference(for: game.id) {
                    game.isFavourited = saved.favorite
                    game.lastLaunched = saved.lastPlayed
                    game.preferredTargetID = saved.preferredTargetID
                }
                if let old = discoveredGames.first(where: { $0.id == game.id }) {
                    game.isFavourited = old.isFavourited
                    game.lastLaunched = old.lastLaunched
                }
                rememberFirstSeen(for: game)
                HubGameOptions.shared.apply(to: game)
                refreshed.insert(game)
            }
            discoveredGames = refreshed
            for diagnostic in discoveryDiagnostics { log.notice("Steam discovery: \(diagnostic, privacy: .public)") }
        }

        // legendary (epic games)
        if storefronts.contains(.epicGames) {
            do {
                let installables = try Legendary.getInstallableGames()
                let installed = try Legendary.getInstalledGames()
                
                // add installables that aren't installed
                for game in installables where !installed.contains(where: { $0 == game }) {
                    library.update(with: game)
                }
                
                // installed: merge instead of overwrite
                for fetchedGame in installed {
                    if let existing = library.first(where: { $0 == fetchedGame }) {
                        try existing.merge(with: fetchedGame, requiring: .identicalIgnoredKeys)
                        library.update(with: existing)
                    } else {
                        library.update(with: fetchedGame)
                    }
                }
            } catch {
                log.error("Unable to refresh game data from Epic Games: \(error.localizedDescription)")
                throw error
            }
        }
        
        // TODO: others
        // if storefronts.contains(...) { ... }
    }
}
