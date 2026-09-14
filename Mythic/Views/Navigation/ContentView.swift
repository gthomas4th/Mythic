//
//  ContentView.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 8/9/2023.
//
//  Reference
//  https://github.com/1998code/SwiftUI2-MacSidebar
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import SwiftUI
import SemanticVersion

struct ContentView: View {
    @EnvironmentObject var networkMonitor: NetworkMonitor
    
    @ObservedObject private var updateController: SparkleUpdateController = .shared
    @Bindable private var operationManager: GameOperationManager = .shared

    @State private var appVersion: String = .init()
    @State private var buildNumber: Int = 0
    
    @State private var engineVersion: SemanticVersion?
    
    @AppStorage("hubTheme") private var theme = "lcars"
    @State private var destination = HubDestination.home

    var body: some View {
        Group {
            if theme == "lcars" { console } else { standardNavigation }
        }
        .modifier(HubThemeModifier())
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--render-game-cards") else { return }
            try? await GameDataStore.shared.refreshFromStorefronts()
            let games = GameDataStore.shared.displayLibrary
            let examples = [games.first { $0 is ROMGame }, games.first { $0.title.localizedStandardContains("REBIRTH") }].compactMap { $0 }
            var artwork: [String: URL] = [:]
            for (index, game) in examples.enumerated() {
                if let url = game.verticalImageURL, !url.isFileURL,
                   let (data, _) = try? await URLSession.shared.data(from: url), NSImage(data: data) != nil {
                    let local = URL(fileURLWithPath: "/private/tmp/gamehub-card-art-\(index).image")
                    try? data.write(to: local)
                    artwork[game.title] = local
                }
            }
            for width in [240.0, 300.0] {
                let preview = VStack(alignment: .leading, spacing: 24) {
                    Text("GAME HUB — RECENTLY PLAYED").font(HubTheme.heading(28))
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(examples) { game in
                            GameCard(game: .constant(game), artworkURL: artwork[game.title]).frame(width: width)
                        }
                    }
                }.padding(28).background(HubTheme.canvas)
                    .environmentObject(NetworkMonitor.shared).environment(\.colorScheme, .light)
                let host = NSHostingView(rootView: preview)
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "/private/tmp/gamehub-native-cards-\(Int(width)).png"))
                    }
                }
                let renderer = ImageRenderer(content: preview)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "/private/tmp/gamehub-cards-\(Int(width)).png"))
                }
            }
        }
#endif
    }

    private enum HubDestination: String, CaseIterable {
        case home = "Home", library = "Library", controller = "Controller", sources = "Game Sources"
        case connections = "PC & Xbox", store = "Store", containers = "Containers", accounts = "Accounts", operations = "Operations"
        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .library: "square.grid.2x2.fill"
            case .controller: "gamecontroller.fill"
            case .sources: "externaldrive.fill"
            case .connections: "desktopcomputer"
            case .store: "bag.fill"
            case .containers: "cube.fill"
            case .accounts: "person.2.fill"
            case .operations: "arrow.down.circle.fill"
            }
        }
    }

    private var console: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("GAME HUB").font(HubTheme.heading(28))
                    Text("PERSONAL GAME LIBRARY").font(.system(size: 11, weight: .bold)).tracking(1)
                }
                .foregroundStyle(.white).padding(.trailing, 22)
                .frame(width: 220, height: 94, alignment: .trailing)
                .background(HubTheme.blue, in: UnevenRoundedRectangle(topLeadingRadius: 52, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 0))
                VStack(alignment: .trailing, spacing: 8) {
                    Text(destination.rawValue.uppercased()).font(HubTheme.heading(28)).tracking(2)
                    HStack(spacing: 8) {
                        Capsule().fill(HubTheme.blue)
                        Capsule().fill(HubTheme.purple).frame(width: 90)
                        Capsule().fill(HubTheme.yellow).frame(width: 54)
                    }.frame(height: 20).accessibilityHidden(true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                ScrollView {
                  VStack(spacing: 7) {
                    ForEach(HubDestination.allCases, id: \.self) { item in
                        if item != .operations || !operationManager.queue.isEmpty {
                            Button { destination = item } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.symbol).frame(width: 24)
                                    Text(item.rawValue.uppercased()).font(HubTheme.heading(18)).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 18).frame(height: 51)
                                .foregroundStyle(destination == item ? Color.white : HubTheme.ink)
                                .background(destination == item ? HubTheme.blue : HubTheme.canvas,
                                            in: UnevenRoundedRectangle(topLeadingRadius: 25, bottomLeadingRadius: 25, bottomTrailingRadius: 5, topTrailingRadius: 5))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(destination == item ? .isSelected : [])
                        }
                    }
                    Spacer(minLength: 12)
                    Button { SupportWindowController.show() } label: {
                        Label("Support", systemImage: "questionmark.circle").font(.system(size: 17))
                    }.buttonStyle(.plain).padding(12)
                    RoundedRectangle(cornerRadius: 5).fill(HubTheme.purple).frame(height: 22).accessibilityHidden(true)
                  }.frame(minHeight: 510)
                }.scrollIndicators(.hidden).frame(width: 220)
                NavigationStack {
                    consoleDestination
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HubTheme.canvas)
                .clipShape(.rect(topLeadingRadius: 28, bottomLeadingRadius: 28, bottomTrailingRadius: 8, topTrailingRadius: 8))
            }
            HStack(spacing: 8) {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 28, bottomTrailingRadius: 0, topTrailingRadius: 0)
                    .fill(HubTheme.blue).frame(width: 220)
                Capsule().fill(HubTheme.blue)
                Capsule().fill(HubTheme.green).frame(width: 60)
                Capsule().fill(HubTheme.red).frame(width: 32)
            }.frame(height: 18).accessibilityHidden(true)
        }
        .padding(16).background(HubTheme.panel)
        .frame(minWidth: 900, minHeight: 700)
    }

    @ViewBuilder private var consoleDestination: some View {
        switch destination {
        case .home: HomeView()
        case .library: LibraryView()
        case .controller: ControllerLibraryView()
        case .sources: ROMLibraryView()
        case .connections: ConnectionsView()
        case .store: StoreView()
        case .containers: ContainersView()
        case .accounts: AccountsView()
        case .operations: OperationsView()
        }
    }

    private var standardNavigation: some View {
        NavigationSplitView(
            sidebar: {
                List {
                    Section {
                        Text("GAME HUB").font(HubTheme.heading(28)).tracking(2).padding(.vertical, 10)
                    }
                    Section {
                        NavigationLink(destination: HomeView()) {
                            Label("Home", systemImage: "house")
                                .help("Everything in one place")
                        }
                        
                        NavigationLink(destination: LibraryView()) {
                            Label("Library", systemImage: "books.vertical")
                                .help("View your games")
                        }
                        
                        NavigationLink(destination: ControllerLibraryView()) {
                            Label("Controller View", systemImage: "gamecontroller.fill")
                        }
                        NavigationLink(destination: ROMLibraryView()) {
                            Label("Game Sources", systemImage: "gamecontroller")
                        }
                        NavigationLink(destination: ConnectionsView()) {
                            Label("Home PC & Xbox", systemImage: "desktopcomputer")
                        }
                        NavigationLink(destination: StoreView()) {
                            Label("Store", systemImage: "bag")
                                .help("Purchase new games from Epic")
                        }
                    }
                    
                    Section {
                        NavigationLink(destination: ContainersView()) {
                            Label("Containers", systemImage: "cube")
                                .help("Manage containers for Windows® applications")
                        }
                        
                        Button("Support", systemImage: "questionmark.bubble") {
                            SupportWindowController.show()
                        }
                        .help("Get support")
                        .buttonStyle(.plain)
                        
                        NavigationLink(destination: AccountsView()) {
                            Label("Accounts", systemImage: "person.2")
                                .help("View all currently signed in accounts")
                        }
                    } header: {
                        Text("Management")
                    }
                }

                // separate downloads view from main list because alignment doesn't work within the main list
                if !operationManager.queue.isEmpty {
                    List { // must wrap in a list to have the same styling as the other links
                        NavigationLink(destination: OperationsView()) {
                            Label("Operations", systemImage: "progress.indicator")
                                .help("View all active game operations")
                        }
                    }
                    .frame(maxHeight: 40)
                    .scrollDisabled(true)
                    .scrollIndicators(.hidden)
                }
                
#if DEBUG
                VStack {
                    if let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                       let mythicVersion: SemanticVersion = .init("\(shortVersion)+\(bundleVersion)") {
                        Text("Mythic \(mythicVersion.prettyString)")
                    }
                    
                    if let engineVersion {
                        Text("Mythic Engine \(engineVersion.prettyString)")
                    }
                }
                .task { @MainActor in
                    engineVersion = await Engine.installedVersion
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
#endif // DEBUG

                switch updateController.state {
                case .updateAvailable:
                    updateBlock("Update Available", buttonText: "Show More") {
                        updateController.checkForUpdates(userInitiated: true)
                    }
                case .readyToRelaunch(let acknowledgement):
                    updateBlock("Update Ready", buttonText: "Relaunch") {
                        acknowledgement(.update)
                    }
                default:
                    EmptyView()
                }
            }, detail: {
                HomeView()
            }
        )
        .modifier(HubThemeModifier())
        .toolbar {
            ToolbarItem(placement: .status) {
                if !networkMonitor.isConnected {
                    Image(systemName: "network")
                        .symbolVariant(.slash)
                        .help("Mythic is not connected to the internet.")
                }
            }
        }
    }

    @ViewBuilder
    private func updateBlock(_ title: String, buttonText: String, action: @escaping () -> Void) -> some View {
        VStack {
            Label(title, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: action, label: {
                Text(buttonText)
                    .frame(maxWidth: .infinity)
            })
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
        .environmentObject(NetworkMonitor.shared)
}
