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
        
        // load library on initialisation
        library = Set(gamesObserver.value.map({ $0.base }))
        
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
    var displayLibrary: Set<Game> { library.union(discoveredGames) }

    var recent: Game? {
        guard !displayLibrary.allSatisfy({ $0.lastLaunched == nil }) else { return nil }

        return displayLibrary.max {
            $0.lastLaunched ?? .distantPast < $1.lastLaunched ?? .distantPast
        }
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
            discoveryDiagnostics = result.diagnostics
            var refreshed: Set<Game> = []
            for record in result.records {
                guard let target = record.launchTargets.first else { continue }
                let game = SteamGame(record: record, target: target)
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
