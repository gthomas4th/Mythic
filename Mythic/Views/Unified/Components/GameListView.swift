//
//  GameListView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 6/3/2024.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI

struct GameListView: View {
    @Bindable var viewModel: GameListViewModel = .shared
    @Bindable var gameDataStore: GameDataStore = .shared
    
    @CodableAppStorage("gameListLayout") var layout: GameListViewModel.Layout = .grid
    @AppStorage("gameCardSize") private var gameCardSize: Double = 200.0
    
    @State private var isSteamDeckLibraryPresented = false
    @ObservedObject private var deckLibrary = SteamDeckLibraryStore.shared

    @State private var isGameImportViewPresented: Bool = false
    
    var body: some View {
        VStack {
            if gameDataStore.displayLibrary.isEmpty {
                ContentUnavailableView(
                    "Your library starts here",
                    systemImage: "folder.badge.questionmark",
                    description: Text("""
                        Install a Mac game in Steam, then refresh to see it here.
                        Import local games below, or open Steam Deck to track your ROM shortcuts.
                        """)
                )
                .task {
                    try? await gameDataStore.refreshFromStorefronts()
                }
                
                Button {
                    isGameImportViewPresented = true
                } label: {
                    Label("Import Game", systemImage: "plus.app")
                        .padding(5)
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $isGameImportViewPresented) {
                    GameImportView(isPresented: $isGameImportViewPresented)
                }
            } else {
                ScrollView(.vertical) {
                    // FIXME: sortedLibrary should not be appended to or it'll cause overwrites.
                    // FIXME: a dirtyfix is to directly set to the underlying library
                    switch layout {
                    case .grid:
                        LazyVGrid(columns: [.init(.adaptive(minimum: gameCardSize))]) {
                            ForEach(viewModel.sortedLibrary) { game in
                                GameCard(game: .constant(game))
                            }
                        }
                        .padding()
                    case .list:
                        LazyVStack {
                            ForEach(viewModel.sortedLibrary) { game in
                                ListGameCard(game: .constant(game))
                            }
                        }
                        .padding()
                    }
                }
                .searchable(text: $viewModel.searchString,
                            tokens: $viewModel.searchTokens,
                            suggestedTokens: .constant(viewModel.suggestedTokens),
                            placement: .toolbar) { token in
                    switch token {
                    case .platform(let platform):
                        Text(platform.description)
                    case .storefront(let storefront):
                        Text(storefront.description)
                    case .installed:
                        Text("Installed")
                    case .notInstalled:
                        Text("Not Installed")
                    case .favourited:
                        Text("Favourited")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    isSteamDeckLibraryPresented = true
                } label: {
                    Label(deckLibrary.inventory.shortcuts.isEmpty ? "Steam Deck" : "Steam Deck (\(deckLibrary.inventory.shortcuts.count))",
                          systemImage: "gamecontroller")
                }
                .help("Import and view Steam Deck ROM shortcuts")
            }
        }
        .sheet(isPresented: $isSteamDeckLibraryPresented) { SteamDeckLibraryView() }
        .animation(.easeInOut, value: layout)
        .animation(.default, value: viewModel.sortedLibrary)
    }
}
    
#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}
