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
    
    @AppStorage("hubTheme") private var hubTheme = "lcars"
    @State private var isSteamDeckLibraryPresented = false
    @ObservedObject private var deckLibrary = SteamDeckLibraryStore.shared

    @State private var isGameImportViewPresented: Bool = false
    
    @State private var input = HubControllerInput.shared
    @State private var selection = 0
    @State private var gridColumns = 1
    @State private var launchMessage = ""
    private func updateColumns(_ width: CGFloat) {
        let cellWidth = max(240.0, gameCardSize) + 22.0
        gridColumns = max(1, Int((Double(width) - 34.0) / cellWidth))
    }
    private func controllerAction(_ action: String) -> Bool {
        if action == "back" || action == "sidebar" { return false }
        if action == "filter" {
            let systems = [""] + viewModel.availableSystems
            let current = systems.firstIndex(of: viewModel.selectedSystem) ?? 0
            viewModel.selectedSystem = systems[(current + 1) % systems.count]
            selection = 0
            return true
        }
        let games = viewModel.sortedLibrary
        guard !games.isEmpty else { return false }
        selection = min(selection, games.count - 1)
        switch action {
        case "left": selection = max(0, selection - 1)
        case "right": selection = min(games.count - 1, selection + 1)
        case "up": selection = max(0, selection - (layout == .grid ? gridColumns : 1))
        case "down": selection = min(games.count - 1, selection + (layout == .grid ? gridColumns : 1))
        case "options": HubGameOptions.shared.open(games[selection])
        case "select":
            let game = games[selection]
            Task { do { try await game.launch(); launchMessage = "" } catch { launchMessage = error.localizedDescription } }
        default: return false
        }
        return true
    }
    private func focusColor(_ game: Game, selectedID: String?) -> Color {
        input.connected && input.contentFocused && selectedID == game.id ? HubTheme.yellow : Color.clear
    }
    @ViewBuilder private func libraryCard(_ game: Game, selectedID: String?) -> some View {
        let outline = RoundedRectangle(cornerRadius: 12).stroke(focusColor(game, selectedID: selectedID), lineWidth: 3)
        if layout == .grid {
            GameCard(game: .constant(game)).padding(4).overlay(outline).id(game.id)
        } else {
            ListGameCard(game: .constant(game)).padding(4).overlay(outline).id(game.id)
        }
    }
    var body: some View {
        let displayedGames = viewModel.sortedLibrary
        let selectedID = displayedGames.indices.contains(selection) ? displayedGames[selection].id : nil
        VStack(spacing: 0) {
            HubSectionBanner(title: "Your library", subtitle: "\(displayedGames.count) games · Pick your next adventure")
                .padding(.horizontal, 28).padding(.vertical, 16)
            if input.connected {
                HubControllerHints(actions: [("Move", "Move"), ("A", "Play"), ("X", "Options"), ("Y", "System"), ("B", "Sidebar")]).padding(.bottom, 12)
            }
            if !launchMessage.isEmpty { Text(launchMessage).padding(8) }
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
            if !gameDataStore.displayLibrary.isEmpty && displayedGames.isEmpty {
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
                ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    // FIXME: sortedLibrary should not be appended to or it'll cause overwrites.
                    // FIXME: a dirtyfix is to directly set to the underlying library
                    switch layout {
                    case .grid:
                        LazyVGrid(columns: [.init(.adaptive(minimum: max(240, gameCardSize)), spacing: 22)], spacing: 24) {
                            ForEach(displayedGames) { game in
                                libraryCard(game, selectedID: selectedID)
                            }
                        }
                        .padding(28)
                    case .list:
                        LazyVStack {
                            ForEach(displayedGames) { game in
                                libraryCard(game, selectedID: selectedID)
                            }
                        }
                        .padding(28)
                    }
                }
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { updateColumns(geometry.size.width) }
                        .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
                })
                .onChange(of: selection) { _, _ in if let selectedID { proxy.scrollTo(selectedID, anchor: .center) } }
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
                        Text("Favorited")
                    }
                }
                }
            }
        }
        .onAppear { input.setContent("library", action: controllerAction) }
        .onDisappear { input.clearContent("library") }
        .onChange(of: displayedGames.map(\.id)) { _, games in selection = min(selection, max(0, games.count - 1)) }
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
        .animation(.easeInOut, value: layout)
        .animation(.default, value: displayedGames)
    }
}
    
#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}
