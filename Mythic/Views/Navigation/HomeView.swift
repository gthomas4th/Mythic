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
    @AppStorage("hubTheme") private var theme = "lcars"

    private var favouriteGames: [Game] {
        gameDataStore.displayLibrary
            .filter(\.self.isFavourited)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                HubSectionBanner(title: "Welcome back", subtitle: "Choose a game and make yourself at home.").padding(.horizontal, 28).padding(.top, 20)

                if let recentGame = gameDataStore.recent {
                    HStack(spacing: 0) {
                        GameImageCard(game: recentGame, url: recentGame.horizontalImageURL ?? recentGame.verticalImageURL,
                                      isImageEmpty: $isImageEmpty, withBlur: false)
                            .frame(width: max(260, (geometry.size.width - 56) * 0.53), height: 300)
                            .clipped()
                        VStack(alignment: .leading, spacing: 18) {
                            Text("CONTINUE PLAYING").font(HubTheme.heading(18)).tracking(2)
                                .foregroundStyle(HubTheme.blue)
                            Text(recentGame.title).font(HubTheme.heading(36)).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(recentGame.sourceLabel.uppercased()).font(.system(size: 15, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(HubTheme.canvas, in: .capsule)
                            Spacer(minLength: 0)
                            GameCard.ButtonsView(game: .constant(recentGame), withLabel: true)
                                .controlSize(.large)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 300)
                    .background(theme == "lcars" ? HubTheme.panel : Color(nsColor: .controlBackgroundColor))
                    .clipShape(.rect(cornerRadius: 24))
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
                    if favouriteGames.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Favourites").font(.title2.bold())
                            Text("Favourite a game from its options menu to keep it here.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        gameRow("Favourites", games: favouriteGames)
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
        }
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(title.uppercased()).font(HubTheme.heading(30)).tracking(1)
                    RoundedRectangle(cornerRadius: 4).fill(HubTheme.blue.opacity(0.35)).frame(height: 10)
                    Text(String(games.count)).font(HubTheme.heading(20))
                        .padding(.horizontal, 16).padding(.vertical, 5)
                        .background(HubTheme.purple.opacity(0.25), in: .capsule)
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(games.prefix(20))) { game in
                            GameCard(game: .constant(game)).frame(width: max(260, gameCardSize))
                        }
                    }
                }
            }
        }
    }

}

#Preview {
    HomeView()
        .environmentObject(NetworkMonitor.shared)
}
