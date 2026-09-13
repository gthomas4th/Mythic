//
//  GameDataStore.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 2/12/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import Combine
import OSLog

// TODO: eventually, migrate to SwiftData.
@Observable @MainActor final class GameDataStore {
    static let shared: GameDataStore = .init()
    let log: Logger = .custom(category: "GameDataStore")
    
    private var catalog: CatalogStore?
    private(set) var persistenceError: String?
    private let gamesObserver: CodableUserDefaultsObserver<[AnyGame]>
    private var isUpdatingFromObserver = false
    
    var library: Set<Game> = .init() {
        didSet {
            guard !isUpdatingFromObserver else { return }
            try? UserDefaults.standard.encodeAndSet(library.map({ AnyGame($0) }), forKey: "games")
        }
    }

    @MainActor private init() {
        // initialise observer
        gamesObserver = .init(key: "games",
                              defaultValue: [])
        
        do {
            catalog = try CatalogStore(url: GameHubRuntime.support.appendingPathComponent("Catalog/catalog.sqlite"))
        } catch { persistenceError = "The saved catalog could not be opened. Existing data has been preserved." }
        // load library on initialisation
        library = Set(gamesObserver.value.map({ $0.base }))
        
        importLegacyCatalog()
        for game in library { restorePreferences(for: game) }
        if let cached = try? catalog?.records() {
            discoveredGames = Set(cached.filter { $0.id.provider == .steam }.compactMap { record in
                guard let target = record.launchTargets.first else { return nil }
                let game = SteamGame(record: record, target: target)
                if let saved = try? catalog?.preference(for: game.id) {
                    game.isFavourited = saved.favorite; game.lastLaunched = saved.lastPlayed
                    game.preferredTargetID = saved.preferredTargetID
                }
                return game
            })
        }
        // observe external changes
        gamesObserver.$value
            .sink { [weak self] newGames in
                guard let self else { return }
                let newLibrary = Set(newGames.map({ $0.base }))
                
                guard newLibrary != self.library else { return }
                self.log.debug("Games key changed in UserDefaults, updating library")
                
                self.isUpdatingFromObserver = true
                defer { self.isUpdatingFromObserver = false }
                self.library = newLibrary
            }
            .store(in: &cancellables)
    }
    
    @ObservationIgnored
    private var cancellables: Set<AnyCancellable> = .init()

    private(set) var discoveredGames: Set<Game> = []
    private(set) var discoveryDiagnostics: [String] = []
    var displayLibrary: Set<Game> { library.union(discoveredGames).union(ROMLibrary.shared.games) }

    var recent: Game? {
        guard !displayLibrary.allSatisfy({ $0.lastLaunched == nil }) else { return nil }

        return displayLibrary.max {
            $0.lastLaunched ?? .distantPast < $1.lastLaunched ?? .distantPast
        }
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
            for game in library where !existing.contains(identity(for: game)) {
                let record = GameRecord(id: .init(provider: game.storefront == .epicGames ? .epic : .local, externalID: game.id),
                    title: game.title, launchTargets: [], artwork: game.verticalImageURL)
                try catalog?.upsert([record])
                try catalog?.setPreference(.init(favorite: game.isFavourited, lastPlayed: game.lastLaunched), for: identity(for: game))
            }
        } catch { persistenceError = "The existing library could not be imported. Its original data is preserved." }
    }
    func restorePreferences(for game: Game) {
        if let saved = try? catalog?.preference(for: identity(for: game)) {
            game.isFavourited = saved.favorite; game.lastLaunched = saved.lastPlayed
        }
    }
    func savePreferences(for game: Game) {
        do {
            try catalog?.setPreference(.init(favorite: game.isFavourited, lastPlayed: game.lastLaunched,
                preferredTargetID: (game as? SteamGame)?.preferredTargetID), for: identity(for: game))
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
            do { try catalog?.upsert(records) } catch { persistenceError = "Library changes could not be saved." }
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
