import SwiftUI
@preconcurrency import GameController

@MainActor @Observable final class HubControllerInput {
    var connected = false
    var onAction: ((String) -> Void)?
    private var observers: [NSObjectProtocol] = []
    func start() {
        stop()
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.bind() }
            })
        }
        bind()
    }
    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            for button in [pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right, pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.buttonMenu] {
                button.pressedChangedHandler = nil
            }
        }
    }
    private func bind() {
        connected = !GCController.controllers().isEmpty
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            for (button, action) in [(pad.dpad.up, "up"), (pad.dpad.down, "down"), (pad.dpad.left, "left"),
                (pad.dpad.right, "right"), (pad.buttonA, "select"), (pad.buttonB, "back"), (pad.buttonX, "favorite"), (pad.buttonY, "filter"), (pad.buttonMenu, "settings")] {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed else { return }
                    Task { @MainActor in
                        guard NSApp.isActive else { return }
                        self?.onAction?(action)
                    }
                }
            }
        }
    }
}
struct ControllerLibraryView: View {
    @State private var input = HubControllerInput()
    @AppStorage("hubTheme") private var theme = "lcars"
    @State private var selection = 0
    @State private var details = false
    @State private var favoritesOnly = false
    @State private var message = ""
    @State private var search = ""
    @State private var showLaunchSettings = false
    @State private var detailProfile: CompatibilityProfile?
    private enum Focus: Hashable { case search, browsing }
    @FocusState private var focus: Focus?
    private var games: [Game] {
        GameDataStore.shared.displayLibrary.filter {
            (!favoritesOnly || $0.isFavourited) && (search.isEmpty || $0.title.localizedStandardContains(search))
        }.sorted { $0.title < $1.title }
    }
    private var selected: Game? { games.indices.contains(selection) ? games[selection] : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("PLAY").font(HubTheme.heading(38)).tracking(2)
                Spacer()
                Label(input.connected ? "Controller connected" : "Keyboard ready", systemImage: "gamecontroller")
            }
            TextField("Search games", text: $search).textFieldStyle(.roundedBorder).focused($focus, equals: .search)
                .onSubmit { details = selected != nil; focus = .browsing }
            Text("↑ ↓ Browse · A / Return Details & Play · B / Escape Back · X Favorite · Y Favorites filter")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            if details, let game = selected {
                Text(game.title).font(HubTheme.heading(36))
                if let steam = game as? SteamGame, let record = steam.record {
                    let target = displayedTarget(for: steam, record: record)
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Play on", value: targetName(target?.kind))
                        LabeledContent("Availability", value: target?.available == true ? "Ready to launch" : "Checked again when you launch")
                        LabeledContent("Controller", value: input.connected ? "Connected to this Mac" : "Not connected")
                        if target?.kind == .wineSteam {
                            LabeledContent("Compatibility", value: detailProfile?.validation == "owner-accepted" ? "Accepted by you" : "Not yet accepted")
                            if let profile = detailProfile {
                                let width = profile.arguments.first { $0.hasPrefix("-ResX=") }?.dropFirst(6)
                                let height = profile.arguments.first { $0.hasPrefix("-ResY=") }?.dropFirst(6)
                                if let width, let height { LabeledContent("Launch resolution", value: "\(width) × \(height)") }
                            }
                            Button("Advanced Launch Settings") { showLaunchSettings = true }
                            Text("Menu / S · Launch settings").font(.caption).foregroundStyle(.secondary)
                        } else if target?.kind == .moonlight {
                            Text("Streams from your Home PC. Its game settings and saves are used.")
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                        }
                    }
                    .task(id: target?.profileID) {
                        detailProfile = target?.profileID.flatMap { try? GameHubRuntime.profiles.load($0) }
                    }
                    if record.launchTargets.count > 1 { Text("← → Change launch target").font(.caption) }
                }
                HStack {
                    Button(game.isLaunching ? "Starting…" : "Play") { play(game) }.disabled(game.isLaunching)
                    Button("Back") { details = false }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(games.enumerated()), id: \.element.id) { position, game in
                                Button {
                                    selection = position; details = true
                                } label: {
                                    HStack {
                                        Image(systemName: game.isFavourited ? "star.fill" : "gamecontroller")
                                        Text(game.title).font(.system(size: 21, weight: .medium))
                                        Spacer()
                                        HubGameBadges(game: game)
                                    }.padding(20).frame(maxWidth: .infinity)
                                        .background(selection == position ? Color.accentColor.opacity(0.25) : (theme == "lcars" ? HubTheme.panel : Color.secondary.opacity(0.08)), in: .rect(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selection == position ? Color.accentColor : .clear, lineWidth: 2))
                                }.buttonStyle(.plain).id(position)
                            }
                        }
                    }
                    .onChange(of: selection) { _, value in proxy.scrollTo(value, anchor: .center) }
                }
            }
            if games.isEmpty { ContentUnavailableView("No matching games", systemImage: "gamecontroller", description: Text("Change the filter or add games through Library.")) }
            if !message.isEmpty { Text(message).foregroundStyle(.orange) }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(theme == "lcars" ? HubTheme.canvas : Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Controller Library")
        .focusable()
        .focused($focus, equals: .browsing)
        .onMoveCommand { direction in if focus != .search { action(String(describing: direction)) } }
        .onKeyPress(.return) {
            if focus == .search { details = selected != nil; focus = .browsing } else { action("select") }
            return .handled
        }
        .onKeyPress("x") { guard focus != .search else { return .ignored }; action("favorite"); return .handled }
        .onKeyPress("s") { guard focus != .search, details else { return .ignored }; action("settings"); return .handled }
        .onKeyPress("y") { guard focus != .search else { return .ignored }; action("filter"); return .handled }
        .onExitCommand { action("back") }
        .onChange(of: search) { _, _ in selection = 0; details = false }
        .sheet(isPresented: $showLaunchSettings) {
            LaunchSettingsView(initialProfileID: detailProfile?.profileID)
        }
        .onAppear { input.onAction = action; input.start(); focus = .browsing }
        .onDisappear { input.stop(); input.onAction = nil }
    }
    private func displayedTarget(for game: SteamGame, record: GameRecord) -> LaunchTarget? {
        record.launchTargets.first { $0.id == game.preferredTargetID && $0.kind == .moonlight }
            ?? LaunchResolver.resolve(record.launchTargets, preferredID: game.preferredTargetID)
    }
    private func targetName(_ kind: LaunchTarget.Kind?) -> String {
        switch kind {
        case .wineSteam: "This Mac · Windows Steam"
        case .nativeMac: "This Mac · Native"
        case .moonlight: "Home PC"
        case .emulator: "This Mac · Emulator"
        case .webCloud: "Cloud"
        case nil: "Unavailable"
        }
    }
    private func action(_ action: String) {
        if showLaunchSettings {
            if action == "back" || action == "settings" { showLaunchSettings = false }
            return
        }
        switch action {
        case "up": if !details { selection = max(0, selection - 1) }
        case "down": if !details { selection = min(max(0, games.count - 1), selection + 1) }
        case "select": if details, let game = selected { play(game) } else { details = true }
        case "settings": if details, detailProfile != nil { showLaunchSettings = true }
        case "back": details = false
        case "favorite": if let game = selected { game.isFavourited.toggle(); GameDataStore.shared.savePreferences(for: game) }
        case "filter": favoritesOnly.toggle(); selection = 0; details = false
        case "left", "right":
            if details, let game = selected as? SteamGame, let record = game.record {
                let targets = record.launchTargets.filter(\.available)
                guard !targets.isEmpty else { return }
                let old = targets.firstIndex(where: { $0.id == game.preferredTargetID }) ?? 0
                game.preferredTargetID = targets[(old + (action == "right" ? 1 : targets.count - 1)) % targets.count].id
                GameDataStore.shared.savePreferences(for: game)
            }
        default: break
        }
    }
    private func play(_ game: Game) {
        Task {
            do { try await game.launch(); message = "" } catch { message = error.localizedDescription }
        }
    }
}
