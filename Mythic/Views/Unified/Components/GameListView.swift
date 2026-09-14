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
    
    
    @AppStorage("hubTheme") private var hubTheme = "lcars"
    @State private var isSteamDeckLibraryPresented = false
    @ObservedObject private var deckLibrary = SteamDeckLibraryStore.shared

    @State private var isGameImportViewPresented: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HubSectionBanner(title: "Your library", subtitle: "\(viewModel.sortedLibrary.count) games · Pick your next adventure")
                .padding(.horizontal, 28).padding(.vertical, 16)
            HStack(spacing: 16) {
                Picker("System", selection: $viewModel.selectedSystem) {
                    Text("All systems").tag("")
                    ForEach(viewModel.availableSystems, id: \.self) { system in
                        Text(system).tag(system)
                    }
                }.pickerStyle(.menu).frame(maxWidth: 340).controlSize(.large)
                if !viewModel.selectedSystem.isEmpty {
                    Button("Clear system") { viewModel.selectedSystem = "" }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 28).padding(.bottom, 16)
            if !gameDataStore.displayLibrary.isEmpty && viewModel.sortedLibrary.isEmpty {
                ContentUnavailableView("No matching games", systemImage: "line.3.horizontal.decrease",
                    description: Text("Try another system or clear your search and filters."))
                Button("Clear all filters") {
                    viewModel.selectedSystem = ""; viewModel.searchString = ""; viewModel.searchTokens = []
                }.padding(.bottom, 16)
            }
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
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.sortedLibrary) { game in
                            GameCard(game: .constant(game))
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 28)
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
        .background(hubTheme == "lcars" ? HubTheme.canvas : Color(nsColor: .windowBackgroundColor))
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
        .animation(.default, value: viewModel.sortedLibrary)
    }
}
    
#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}
