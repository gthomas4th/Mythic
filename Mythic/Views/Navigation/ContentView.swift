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
    @State private var controller = HubControllerInput.shared
    @State private var gameOptions = HubGameOptions.shared
    @State private var sidebarFocused = true
    @State private var sidebarSelection = HubDestination.home
    private var destinations: [HubDestination] {
        HubDestination.allCases.filter { $0 != .containers && ($0 != .operations || !operationManager.queue.isEmpty) }
    }
    private func controllerAction(_ action: String) {
        if gameOptions.action(action) { return }
        if action == "settings" {
            _ = controller.contentAction?("sidebar")
            sidebarFocused = true; sidebarSelection = destination; return
        }
        if !sidebarFocused {
            if controller.contentAction?(action) == true { return }
            if action == "back" || action == "left" {
                sidebarFocused = true; sidebarSelection = destination
            }
            return
        }
        let items = destinations
        let index = items.firstIndex(of: sidebarSelection) ?? 0
        switch action {
        case "up": sidebarSelection = items[max(0, index - 1)]
        case "down": sidebarSelection = items[min(items.count - 1, index + 1)]
        case "select", "right":
            destination = sidebarSelection; sidebarFocused = false
        case "back": sidebarFocused = false
        default: break
        }
    }

    var body: some View {
        Group {
            if theme == "lcars" { console } else { standardNavigation }
        }
        .safeAreaInset(edge: .bottom) {
            if !ROMLibrary.shared.downloadStatus.isEmpty {
                HStack {
                    Text(ROMLibrary.shared.downloadStatus).font(.system(size: 15))
                    Spacer()
                    if ROMLibrary.shared.downloadingID != nil {
                        Button("Cancel download") { ROMLibrary.shared.cancelDownload() }
                    } else {
                        Button("Dismiss") { ROMLibrary.shared.downloadStatus = "" }
                    }
                }.padding().background(HubTheme.canvas)
            }
        }
        .modifier(HubThemeModifier())
        .sheet(item: $gameOptions.game) { _ in HubGameOptionsView() }
        .onChange(of: sidebarFocused) { _, value in controller.contentFocused = !value }
        .onAppear { controller.contentFocused = !sidebarFocused; controller.onAction = controllerAction; controller.start() }
        .onDisappear { controller.stop(); controller.onAction = nil }
#if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--test-controller-navigation") else { return }
            try? await Task.sleep(for: .milliseconds(300))
            var failures: [String] = []
            controllerAction("settings")
            if !sidebarFocused { failures.append("Menu did not focus sidebar") }
            let old = sidebarSelection
            controllerAction("down")
            if sidebarSelection == old { failures.append("Sidebar did not move down") }
            sidebarSelection = .controller
            controllerAction("select")
            try? await Task.sleep(for: .milliseconds(500))
            if destination != .controller || sidebarFocused { failures.append("A did not enter controller library") }
            if controller.contentAction == nil { failures.append("Content handler missing") }
            if !GameDataStore.shared.displayLibrary.isEmpty {
                let launchCount = Game.controllerTestLaunches.count
                controllerAction("select")
                try? await Task.sleep(for: .milliseconds(100))
                if Game.controllerTestLaunches.count != launchCount + 1 { failures.append("Controller A did not activate Play directly") }
                controllerAction("options")
                controllerAction("back")
                if sidebarFocused { failures.append("Options B skipped game list") }
            }
            controllerAction("back")
            if !sidebarFocused { failures.append("B did not return to sidebar") }
            controllerAction("select")
            controllerAction("settings")
            if !sidebarFocused { failures.append("Menu did not re-enter sidebar") }
            sidebarSelection = .home; controllerAction("select")
            try? await Task.sleep(for: .milliseconds(300))
            if !GameDataStore.shared.displayLibrary.isEmpty {
                controllerAction("down")
                controllerAction("right")
                if sidebarFocused { failures.append("Home navigation left content") }
                controllerAction("options")
                if gameOptions.game == nil { failures.append("Home X did not open options") }
                let homeGameID = gameOptions.game?.id
                controllerAction("back")
                let homeLaunchCount = Game.controllerTestLaunches.count
                controllerAction("select")
                try? await Task.sleep(for: .milliseconds(100))
                if Game.controllerTestLaunches.count != homeLaunchCount + 1 || Game.controllerTestLaunches.last != homeGameID { failures.append("Home A did not play selected game") }
                controllerAction("options")
                let originalTitle = gameOptions.game?.title
                for _ in 0..<3 { controllerAction("down") }
                controllerAction("select")
                if gameOptions.editor != "Title" { failures.append("Title editor did not open") }
                let originalDraft = gameOptions.draft
                controllerAction("select")
                if gameOptions.draft != originalDraft + "a" { failures.append("Controller keyboard did not type") }
                controllerAction("back")
                if gameOptions.editor != nil || gameOptions.game?.title != originalTitle { failures.append("Editor cancel failed") }
                controllerAction("back")
                if gameOptions.game != nil || sidebarFocused { failures.append("Options B did not return Home") }
                controllerAction("options")
                controllerAction("settings")
                if gameOptions.game != nil || !sidebarFocused { failures.append("Options Menu did not return sidebar") }
                sidebarSelection = .library; controllerAction("select")
                try? await Task.sleep(for: .milliseconds(300))
                controllerAction("options")
                if gameOptions.game == nil { failures.append("Library X did not open options") }
                let libraryGameID = gameOptions.game?.id
                controllerAction("back")
                let libraryLaunchCount = Game.controllerTestLaunches.count
                controllerAction("select")
                try? await Task.sleep(for: .milliseconds(100))
                if Game.controllerTestLaunches.count != libraryLaunchCount + 1 || Game.controllerTestLaunches.last != libraryGameID { failures.append("Library A did not play selected game") }
            }
            controllerAction("back")
            if !sidebarFocused { failures.append("B did not return from content") }
            let editFile = FileManager.default.temporaryDirectory.appendingPathComponent("gamehub-edit-test-" + UUID().uuidString + ".json")
            let sample = LocalGame(id: "controller-test", title: "Original", installationState: .uninstalled)
            let editTest = HubGameOptions(file: editFile)
            editTest.open(sample); editTest.editor = "Title"; editTest.draft = "Controller title"; editTest.saveEdit()
            let restored = LocalGame(id: "controller-test", title: "Original", installationState: .uninstalled)
            HubGameOptions(file: editFile).apply(to: restored)
            if restored.title != "Controller title" { failures.append("Title edit did not survive reload") }
            editTest.editor = "Artwork URL"; editTest.draft = "file:///private/test"; editTest.saveEdit()
            if editTest.editor == nil || sample._verticalImageURL != nil { failures.append("Invalid artwork URL was accepted") }
            try? FileManager.default.removeItem(at: editFile)
            let started = Date()
            for _ in 0..<100 { _ = GameDataStore.shared.displayLibrary.count }
            let report: [String: Any] = ["passed": failures.isEmpty, "failures": failures,
                "controllerConnected": controller.connected, "catalogReads100Milliseconds": Date().timeIntervalSince(started) * 1000]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: "/private/tmp/gamehub-controller-navigation-test.json"))
            }
        }
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
        case connections = "PC & PS5", store = "Store", containers = "Containers", accounts = "Accounts", operations = "Operations"
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
                ScrollViewReader { sidebarProxy in
                ScrollView {
                  VStack(spacing: 7) {
                    ForEach(HubDestination.allCases, id: \.self) { item in
                        if item != .containers && (item != .operations || !operationManager.queue.isEmpty) {
                            Button { destination = item; sidebarSelection = item; sidebarFocused = false } label: {
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
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(controller.connected && sidebarFocused && sidebarSelection == item ? HubTheme.yellow : .clear, lineWidth: 3))
                                .accessibilityAddTraits(destination == item ? .isSelected : [])
                                .id(item)
                        }
                    }
                    if controller.connected {
                        VStack(alignment: .leading, spacing: 8) {
                            if sidebarFocused {
                                HubButtonHint(button: "Move", action: "Choose")
                                HubButtonHint(button: "A", action: "Open")
                            } else {
                                HubButtonHint(button: "B", action: "Back")
                                HubButtonHint(button: "Menu", action: "Sidebar")
                            }
                        }.padding(.vertical, 8)
                    }
                    Spacer(minLength: 12)
                    Button { SupportWindowController.show() } label: {
                        Label("Support", systemImage: "questionmark.circle").font(.system(size: 17))
                    }.buttonStyle(.plain).padding(12)
                    RoundedRectangle(cornerRadius: 5).fill(HubTheme.purple).frame(height: 22).accessibilityHidden(true)
                  }.frame(minHeight: 510)
                }.scrollIndicators(.hidden)
                    .onChange(of: sidebarSelection) { _, value in sidebarProxy.scrollTo(value, anchor: .center) }
                }.frame(width: 220)
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
                        ForEach(destinations, id: \.self) { item in
                            Button {
                                destination = item; sidebarSelection = item; sidebarFocused = false
                            } label: {
                                Label(item.rawValue, systemImage: item.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                                    .background(controller.connected && sidebarFocused && sidebarSelection == item ? HubTheme.yellow.opacity(0.5) : .clear)
                            }.buttonStyle(.plain)
                        }
                        Button("Support") { SupportWindowController.show() }
                    }
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
                NavigationStack { consoleDestination }
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
