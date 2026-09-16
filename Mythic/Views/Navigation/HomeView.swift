//
//  HomeView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 12/9/2023.
//

// Copyright © 2023-2025 vapidinfinity

import SwiftUI
import Cocoa
import Glur
import Shimmer
import SwordRPC

/**
 The main view displaying the home screen of the Mythic app.
 */
struct HomeView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @Bindable var gameDataStore: GameDataStore = .shared
    
    @AppStorage("gameCardSize") private var gameCardSize: Double = 200.0
    
    @State private var isImageEmpty = true
    @State private var input = HubControllerInput.shared
    @State private var shelfIndex = 0
    @State private var column = 0
    @State private var launchMessage = ""
    private var shelves: [(String, [Game])] {
        var rows: [(String, [Game])] = []
        if let recent = gameDataStore.recent { rows.append(("Continue", [recent])) }
        rows += [("Favorites", favouriteGames),
            ("Recently Played", gameDataStore.displayLibrary.filter { $0.lastLaunched != nil && $0 != gameDataStore.recent }.sorted { ($0.lastLaunched ?? .distantPast) > ($1.lastLaunched ?? .distantPast) }),
            ("Recently Added", gameDataStore.recentlyAdded),
            ("Final Fantasy", sortedGames.filter { $0.title.localizedStandardContains("Final Fantasy") }),
            ("Retro", sortedGames.filter { $0 is ROMGame }),
            ("Ready on Home PC", sortedGames.filter { ($0 as? SteamGame)?.record?.launchTargets.contains { $0.kind == .moonlight && $0.available } == true })]
        return rows.filter { !$0.1.isEmpty }.map { ($0.0, Array($0.1.prefix(20))) }
    }
    private var activeShelf: String { shelves.indices.contains(shelfIndex) ? shelves[shelfIndex].0 : "" }
    private var activeGame: Game? {
        guard shelves.indices.contains(shelfIndex) else { return nil }
        let games = shelves[shelfIndex].1
        return games.indices.contains(column) ? games[column] : games.first
    }
    private func homeAction(_ command: String) -> Bool {
        let rows = shelves
        guard !rows.isEmpty else { return false }
        if command == "back" || command == "sidebar" { return false }
        switch command {
        case "up":
            shelfIndex = max(0, shelfIndex - 1)
            column = min(column, max(0, rows[shelfIndex].1.count - 1))
        case "down":
            shelfIndex = min(rows.count - 1, shelfIndex + 1)
            column = min(column, max(0, rows[shelfIndex].1.count - 1))
        case "left": column = max(0, column - 1)
        case "right": column = min(rows[min(shelfIndex, rows.count - 1)].1.count - 1, column + 1)
        case "options": if let game = activeGame { HubGameOptions.shared.open(game) }
        case "filter": if let game = activeGame { game.isFavourited.toggle(); gameDataStore.savePreferences(for: game) }
        case "select": if let game = activeGame { Task { do { try await game.launch(); launchMessage = "" } catch { launchMessage = error.localizedDescription } } }
        default: return false
        }
        return true
    }
    @AppStorage("hubTheme") private var theme = "lcars"

    private var favouriteGames: [Game] {
        gameDataStore.displayLibrary
            .filter(\.self.isFavourited)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { verticalProxy in
            ScrollView {
                if input.connected { HubControllerHints(actions: [("Move", "Rows / Games"), ("A", "Play"), ("X", "Options"), ("Y", "Favorite"), ("B", "Sidebar")]).padding(.horizontal, 28) }
                if !launchMessage.isEmpty { Text(launchMessage).padding(.horizontal, 28) }
                if let recentGame = gameDataStore.recent {
                    HStack(spacing: 0) {
                        GameImageCard(game: recentGame, url: recentGame.horizontalImageURL ?? recentGame.verticalImageURL,
                                      isImageEmpty: $isImageEmpty, withBlur: false, contentMode: .fit)
                            .frame(width: max(260, (geometry.size.width - 56) * 0.53), height: 300)
                            .clipped()
                        VStack(alignment: .leading, spacing: 18) {
                            Text("CONTINUE PLAYING").font(HubTheme.heading(18)).tracking(2)
                                .foregroundStyle(HubTheme.blue)
                            Text(recentGame.title).font(HubTheme.heading(34)).lineLimit(3)
                                .minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HubGameBadges(game: recentGame)
                            Spacer(minLength: 0)
                            GameCard.ButtonsView(game: .constant(recentGame), withLabel: true, cardLayout: true)
                                .controlSize(.large)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 300)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(input.connected && input.contentFocused && activeShelf == "Continue" ? HubTheme.yellow : .clear, lineWidth: 3))
                    .id("Continue")
                    .padding(.horizontal, 28).padding(.top, 12)
                } else {
                    ContentUnavailableView(
                        "Welcome to Game Hub",
                        systemImage: "hand.wave",
                        description: .init("""
                        This area is where your most recently played game will appear — try launching one now!
                        """)
                    )
                    .frame(
                        width: geometry.size.width,
                        height: min(480, max(320, geometry.size.height * 0.6))
                    )
                    .background(.quinary)
                }
                
                VStack(alignment: .leading, spacing: 28) {
                    if !favouriteGames.isEmpty {
                        gameRow("Favorites", games: favouriteGames)
                    }
                    gameRow("Recently Played", games: gameDataStore.displayLibrary
                        .filter { $0.lastLaunched != nil && $0 != gameDataStore.recent }
                        .sorted { ($0.lastLaunched ?? .distantPast) > ($1.lastLaunched ?? .distantPast) })
                    gameRow("Recently Added", games: gameDataStore.recentlyAdded)
                    gameRow("Final Fantasy", games: sortedGames.filter { $0.title.localizedStandardContains("Final Fantasy") })
                    gameRow("Retro", games: sortedGames.filter { $0 is ROMGame })
                    gameRow("Ready on Home PC", games: sortedGames.filter {
                        ($0 as? SteamGame)?.record?.launchTargets.contains { $0.kind == .moonlight && $0.available } == true
                    })
                }
                .padding(24)

            }
            .onChange(of: shelfIndex) { _, _ in verticalProxy.scrollTo(activeShelf, anchor: .top) }
            }
        }
        .onAppear { input.setContent("home", action: homeAction) }
        .onDisappear { input.clearContent("home") }
        .background(theme == "lcars" ? HubTheme.canvas : Color(nsColor: .windowBackgroundColor))
        .customTransform { view in
            if #available(macOS 15.0, *) {
                view
                    .toolbar(removing: .title)
                    .toolbarBackgroundVisibility(.hidden) // dirtyfixes toolbar reappearance on view reload in navigationsplitview
            } else {
                view
                    .toolbarBackground(.hidden) // dirtyfixes toolbar reappearance on view reload in navigationsplitview
            }
        }

        .navigationTitle("Home")
        .task(priority: .background) {
            discordRPC.setPresence({
                var presence: RichPresence = .init()
                presence.details = "Viewing home"
                presence.state = "Idle"
                presence.timestamps.start = .now
                presence.assets.largeImage = "macos_512x512_2x"
                
                return presence
            }())
        }
    }
    private var sortedGames: [Game] {
        gameDataStore.displayLibrary.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    @ViewBuilder private func gameRow(_ title: String, games: [Game]) -> some View {
        if !games.isEmpty {
            let selected = input.connected && input.contentFocused && activeShelf == title
            let selectedID = selected ? activeGame?.id : nil
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(title.uppercased()).font(HubTheme.heading(26)).lineLimit(1).minimumScaleFactor(0.75)
                    RoundedRectangle(cornerRadius: 4).fill(HubTheme.blue.opacity(0.35)).frame(height: 10)
                    Text(String(games.count)).font(HubTheme.heading(20))
                        .padding(.horizontal, 16).padding(.vertical, 5)
                        .background(HubTheme.purple.opacity(0.25), in: .capsule)
                }
                ScrollViewReader { horizontalProxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(games.prefix(20))) { game in
                            GameCard(game: .constant(game)).frame(width: max(300, gameCardSize))
                                .padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected && selectedID == game.id ? HubTheme.yellow : .clear, lineWidth: 3))
                                .id(game.id)
                        }
                    }
                }
                .onChange(of: column) { _, _ in if activeShelf == title, let game = activeGame { horizontalProxy.scrollTo(game.id, anchor: .center) } }
                }
            }.id(title)
        }
    }

}

#Preview {
    HomeView()
        .environmentObject(NetworkMonitor.shared)
}
