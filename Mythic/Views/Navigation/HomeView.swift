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

    private var favouriteGames: [Game] {
        gameDataStore.displayLibrary
            .filter(\.self.isFavourited)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let recentGame = gameDataStore.recent {
                    ZStack(alignment: .bottomLeading) {
                        GameImageCard(url: recentGame.horizontalImageURL ?? recentGame.verticalImageURL, isImageEmpty: $isImageEmpty)
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: geometry.size.width, height: min(480, max(320, geometry.size.height * 0.6)))
                            .glur(radius: 18,
                                  offset: 0.6,
                                  interpolation: 0.6)
                            .customTransform { view in
                                if #available(macOS 26.0, *) {
                                    view.backgroundExtensionEffect()
                                } else {
                                    view
                                }
                            }

                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            .allowsHitTesting(false)
                        HStack {
                            if isImageEmpty, recentGame.isFallbackImageAvailable {
                                GameImageCard.FallbackGameImageCard(game: .constant(recentGame))
                                    .frame(width: 65, height: 65)
                                    .aspectRatio(contentMode: .fit)
                                    .padding(.trailing)
                            }
                            
                            VStack(alignment: .leading) {
                                Text("CONTINUE PLAYING")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                
                                HStack {
                                    GameCard.TitleAndInformationView(game: .constant(recentGame), withSubscriptedInfo: true)
                                }
                                HStack {
                                    GameCard.ButtonsView(game: .constant(recentGame), withLabel: true)
                                        .clipShape(.capsule)
                                }
                            }
                            .conditionalTransform(if: !isImageEmpty) { view in
                                view
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding([.leading, .bottom])
                    }
                    .frame(height: min(480, max(320, geometry.size.height * 0.6)))
                } else {
                    ContentUnavailableView(
                        "Welcome to Mythic!",
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
        .ignoresSafeArea(edges: .top)
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
                Text(title).font(.title2.bold())
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(games.prefix(20))) { game in
                            GameCard(game: .constant(game)).frame(width: max(240, gameCardSize), height: 340)
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
