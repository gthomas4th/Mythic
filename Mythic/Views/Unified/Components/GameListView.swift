//
//  GameListView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 6/3/2024.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI

enum HubGridNavigation {
    static func destination(from index: Int, action: String, columns: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let columns = max(1, columns)
        let index = min(max(0, index), count - 1)
        let column = index % columns
        switch action {
        case "left": return column > 0 ? index - 1 : index
        case "right": return column < columns - 1 && index + 1 < count ? index + 1 : index
        case "up": return index >= columns ? index - columns : index
        case "down":
            let candidate = index + columns
            return candidate < count ? candidate : index
        default: return index
        }
    }
}

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
    @State private var contentWidth: CGFloat = 1000
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
        case "left", "right", "up", "down":
            if layout == .grid {
                selection = HubGridNavigation.destination(from: selection, action: action, columns: gridColumns, count: games.count)
            } else if action == "up" {
                selection = max(0, selection - 1)
            } else if action == "down" {
                selection = min(games.count - 1, selection + 1)
            }
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
        let connections = gameDataStore.connectionGames.compactMap { $0 as? ConnectionGame }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let selectedID = displayedGames.indices.contains(selection) ? displayedGames[selection].id : nil
        VStack(spacing: 0) {
            HubSectionBanner(title: "Your library")
                .padding(.horizontal, 28).padding(.vertical, 16)
            if input.connected {
                HubControllerHints(actions: [("Move", "Move"), ("A", "Play"), ("X", "Options"), ("Y", "System"), ("B", "Sidebar")]).padding(.bottom, 12)
            }
            if !launchMessage.isEmpty { Text(launchMessage).padding(8) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HubTheme.blue)
                    TextField("Search titles", text: $viewModel.searchString)
                        .textFieldStyle(.plain).font(.system(size: 17))
                    if !viewModel.searchString.isEmpty {
                        Button { viewModel.searchString = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain).help("Clear search")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(HubTheme.panel, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.blue.opacity(0.45), lineWidth: 1))

                Label("QUICK PLAY", systemImage: "bolt.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(HubTheme.ink)
                HStack(spacing: 10) {
                    ForEach(connections) { game in
                        HubConnectionQuickButton(game: game) {
                            Task { do { try await game.launch(); launchMessage = "" } catch { launchMessage = error.localizedDescription } }
                        }
                    }
                }

                Label("SYSTEM", systemImage: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(HubTheme.ink)
                if contentWidth < 850 {
                    Menu {
                        Button("All systems") { viewModel.selectedSystem = ""; selection = 0 }
                        ForEach(viewModel.availableSystems, id: \.self) { system in
                            Button(system) { viewModel.selectedSystem = system; selection = 0 }
                        }
                    } label: {
                        Label(viewModel.selectedSystem.isEmpty ? "All systems" : viewModel.selectedSystem, systemImage: "gamecontroller.fill")
                            .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(HubTheme.blue.opacity(0.18), in: .rect(cornerRadius: 10))
                    }.menuStyle(.borderlessButton)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            HubSystemFilterButton(title: "All", system: nil, selected: viewModel.selectedSystem.isEmpty) {
                                viewModel.selectedSystem = ""; selection = 0
                            }
                            ForEach(viewModel.availableSystems, id: \.self) { system in
                                HubSystemFilterButton(title: system, system: system, selected: viewModel.selectedSystem == system) {
                                    viewModel.selectedSystem = system; selection = 0
                                }
                            }
                        }
                    }
                }

                Label("TITLE", systemImage: "textformat")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(HubTheme.ink)
                if contentWidth < 850 {
                    Menu {
                        Button("All titles") { viewModel.selectedLetter = ""; selection = 0 }
                        ForEach(GameListViewModel.alphabetSections, id: \.self) { letter in
                            Button(letter) { viewModel.selectedLetter = letter; selection = 0 }
                        }
                    } label: {
                        Label(viewModel.selectedLetter.isEmpty ? "All titles" : "Titles beginning with \(viewModel.selectedLetter)", systemImage: "textformat")
                            .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(HubTheme.blue.opacity(0.14), in: .rect(cornerRadius: 10))
                    }.menuStyle(.borderlessButton)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            HubAlphabetFilterButton(title: "All", selected: viewModel.selectedLetter.isEmpty) {
                                viewModel.selectedLetter = ""; selection = 0
                            }
                            ForEach(GameListViewModel.alphabetSections, id: \.self) { letter in
                                HubAlphabetFilterButton(title: letter, selected: viewModel.selectedLetter == letter) {
                                    viewModel.selectedLetter = letter; selection = 0
                                }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 28).padding(.bottom, 16)
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { contentWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in contentWidth = width }
                })
            if !gameDataStore.displayLibrary.isEmpty && displayedGames.isEmpty {
                ContentUnavailableView("No matching games", systemImage: "line.3.horizontal.decrease",
                    description: Text("Try another system or clear your search and filters."))
                Button("Clear all filters") {
                    viewModel.selectedSystem = ""; viewModel.selectedLetter = ""
                    viewModel.searchString = ""; viewModel.searchTokens = []
                }.padding(.bottom, 16)
            }
            if gameDataStore.displayLibrary.isEmpty {
                ContentUnavailableView(
                    "Your library starts here",
                    systemImage: "folder.badge.questionmark",
                    description: Text("""
                        Refresh Steam or Epic, add a ROM source, or import a local game to begin.
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
    }
}
    
#Preview {
    GameListView()
        .environmentObject(NetworkMonitor.shared)
}

private struct HubSystemFilterButton: View {
    let title: String
    let system: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let system { HubSystemMark(system: system, size: 20) }
                else { Image(systemName: "square.grid.2x2.fill") }
                Text(title)
            }
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(selected ? Color.black.opacity(0.86) : HubTheme.ink)
                .background(selected ? HubTheme.yellow : HubTheme.blue.opacity(0.18), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(title) games")
    }
}

private struct HubConnectionQuickButton: View {
    let game: ConnectionGame
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(game.artworkAssetName)
                    .resizable().scaledToFill()
                    .frame(width: 38, height: 38).clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.title).font(.system(size: 16, weight: .bold))
                    Text(game.locationLabel ?? "Remote").font(.system(size: 12, weight: .semibold))
                }
                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(HubTheme.ink)
            .background(HubTheme.blue.opacity(0.18), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.blue.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Launch \(game.title)")
    }
}

private struct HubAlphabetFilterButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold))
                .frame(minWidth: title == "All" ? 34 : 24, minHeight: 28)
                .padding(.horizontal, 4)
                .foregroundStyle(selected ? Color.black.opacity(0.86) : HubTheme.ink)
                .background(selected ? HubTheme.yellow : HubTheme.blue.opacity(0.14), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "All" ? "Show every title" : "Show titles beginning with \(title)")
    }
}
