//
//  GameListViewModel.swift
//  Mythic
//
//  Created by Marcus Ziade on ~23/06/24.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI
import Combine
import OSLog

@Observable @MainActor final class GameListViewModel {
    static let shared: GameListViewModel = .init()

    var selectedSystem: String = ""
    var selectedLetter: String = ""
    var availableSystems: [String] {
        Set(GameDataStore.shared.displayLibrary.map { Self.systemName(for: $0) }).sorted()
    }
    static func systemName(for game: Game) -> String {
        if game is ConnectionGame { return "Connections" }
        guard let rom = game as? ROMGame else { return "PC & Mac" }
        let raw = rom.source?.system.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch raw.lowercased() {
        case "gc", "gamecube", "ngc": return "GameCube"
        case "psx", "ps1", "playstation": return "PlayStation"
        case "ps2", "playstation 2": return "PlayStation 2"
        case "ps3", "playstation 3": return "PlayStation 3"
        case "snes", "super nintendo": return "Super Nintendo"
        case "n64", "nintendo 64": return "Nintendo 64"
        case "genesis", "megadrive", "mega drive", "mega drive / genesis", "sega": return "Sega"
        case "dreamcast": return "Dreamcast"
        case "switch", "nintendo switch": return "Nintendo Switch"
        case "nes": return "NES"
        case "gba": return "Game Boy Advance"
        case "gb": return "Game Boy"
        case "gbc": return "Game Boy Color"
        case "psp": return "PSP"
        case "wii": return "Wii"
        default: return raw.isEmpty ? "Other ROMs" : raw
        }
    }

    static let alphabetSections = ["#"] + (65...90).compactMap { UnicodeScalar($0).map(String.init) }
    static func alphabetSection(for game: Game) -> String {
        let title = (game is ROMGame ? ROMTitle.sortKeyForDisplayName(game.title) : game.title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        guard let first = title.first, first >= "A", first <= "Z" else { return "#" }
        return String(first)
    }

    var searchString: String = .init()
    var searchTokens: [SearchToken] = [] {
        didSet {
            let platforms: [SearchToken] = searchTokens.compactMap { if case .platform = $0 { $0 } else { nil } }
            let storefronts: [SearchToken] = searchTokens.compactMap { if case .storefront = $0 { $0 } else { nil } }
            let installations: [SearchToken] = searchTokens.filter { $0 == .installed || $0 == .notInstalled }
            
            if platforms.count > 1, let last = platforms.last {
                searchTokens.removeAll { if case .platform = $0 { $0 != last } else { false } }
            }
            if storefronts.count > 1, let last = storefronts.last {
                searchTokens.removeAll { if case .storefront = $0 { $0 != last } else { false } }
            }
            if installations.count > 1, let last = installations.last {
                searchTokens.removeAll { ($0 == .installed || $0 == .notInstalled) && $0 != last }
            }
        }
    }
    
    var sortedLibrary: [Game] {
        let operating = Set(Game.operationManager.queue.filter(\.isExecuting).map { $0.game.id })
        return GameDataStore.shared.displayLibrary
            .filter { game in
                let matchesText: Bool = searchString.isEmpty || game.title.localizedStandardContains(searchString)
                let matchesTokens: Bool = searchTokens.isEmpty || searchTokens.allSatisfy { token in
                    switch token {
                    case .platform(let platform):
                        guard case .installed(_, let gamePlatform) = game.installationState else { return false }
                        return gamePlatform == platform
                    case .storefront(let storefront):
                        return game.storefront == storefront
                    case .installed:
                        if case .installed = game.installationState { return true }
                        return false
                    case .notInstalled:
                        if case .uninstalled = game.installationState { return true }
                        return false
                    case .favourited:
                        return game.isFavourited
                    }
                }
                let matchesSystem = selectedSystem.isEmpty || Self.systemName(for: game) == selectedSystem
                let matchesLetter = selectedLetter.isEmpty || Self.alphabetSection(for: game) == selectedLetter
                return matchesText && matchesTokens && matchesSystem && matchesLetter
            }
            .sorted { left, right in
                let leftOperating = operating.contains(left.id), rightOperating = operating.contains(right.id)
                if leftOperating != rightOperating { return leftOperating }
                if left.installationState > right.installationState { return true }
                if right.installationState > left.installationState { return false }
                let leftTitle = left is ROMGame ? ROMTitle.sortKeyForDisplayName(left.title) : left.title
                let rightTitle = right is ROMGame ? ROMTitle.sortKeyForDisplayName(right.title) : right.title
                if leftTitle != rightTitle { return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending }
                return left.id < right.id
            }
    }
    
    var suggestedTokens: [SearchToken] {
        var suggestions: [SearchToken] = []
        
        let hasPlatform: Bool = searchTokens.contains { if case .platform = $0 { true } else { false } }
        let hasStorefront: Bool = searchTokens.contains { if case .storefront = $0 { true } else { false } }
        let hasInstallation: Bool = searchTokens.contains { $0 == .installed || $0 == .notInstalled }
        
        if !hasPlatform { suggestions.append(contentsOf: Game.Platform.allCases.map { .platform($0) }) }
        if !hasStorefront { suggestions.append(contentsOf: Game.Storefront.allCases.map { .storefront($0) }) }
        if !hasInstallation { suggestions += [.installed, .notInstalled] }
        if !searchTokens.contains(.favourited) { suggestions.append(.favourited) }
        
        return suggestions
    }

    private var sortOptions: [SortOptions] = [.favorite, .installed, .title]
    private let logger: Logger = .custom(category: "GameListViewModel")
    
    var isUpdatingLibrary: Bool = false
}

extension GameListViewModel {
    enum SearchToken: Identifiable, Hashable {
        case platform(Game.Platform)
        case storefront(Game.Storefront)
        case installed
        case notInstalled
        case favourited
        
        var id: String {
            switch self {
            case .platform(let platform):
                return "platform_\(platform.description)"
            case .storefront(let storefront):
                return "storefront_\(storefront.description)"
            case .installed:
                return "installed"
            case .notInstalled:
                return "notInstalled"
            case .favourited:
                return "favourited"
            }
        }
    }
    
    struct FilterOptions: OptionSet, Sendable {
        let rawValue: Int
        
        static let installed: FilterOptions = .init(rawValue: 1 << 0)
        static let favourited: FilterOptions = .init(rawValue: 1 << 1)
        
        static let all: FilterOptions = [.installed, .favourited]
    }

    enum Layout: String, CaseIterable, Sendable, Codable, Equatable {
        case grid = "Grid"
        case list = "List"
    }

    enum SortOptions: CaseIterable, Sendable {
        case favorite
        case installed
        case title
    }
}
