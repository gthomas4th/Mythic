import SwiftUI
@preconcurrency import GameController

@MainActor @Observable final class HubControllerInput {
    static let shared = HubControllerInput()
    var connected = false
    var contentAction: ((String) -> Bool)?
    private var stickDirection: String?
    private var stickTask: Task<Void, Never>?
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
        stickTask?.cancel(); stickTask = nil; stickDirection = nil
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            pad.leftThumbstick.valueChangedHandler = nil
            for button in [pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right, pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY, pad.buttonMenu] {
                button.pressedChangedHandler = nil
            }
        }
    }
    private func bind() {
        stickTask?.cancel(); stickTask = nil; stickDirection = nil
        connected = !GCController.controllers().isEmpty
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            pad.leftThumbstick.valueChangedHandler = { [weak self] _, axisX, axisY in
                let direction: String? = max(abs(axisX), abs(axisY)) < 0.55 ? nil : (abs(axisY) >= abs(axisX) ? (axisY > 0 ? "up" : "down") : (axisX > 0 ? "right" : "left"))
                Task { @MainActor in self?.moveStick(direction) }
            }
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
    private func moveStick(_ direction: String?) {
        guard direction != stickDirection else { return }
        stickDirection = direction; stickTask?.cancel()
        guard let direction else { return }
        if NSApp.isActive { onAction?(direction) }
        stickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                while !Task.isCancelled {
                    if NSApp.isActive { self?.onAction?(direction) }
                    try await Task.sleep(for: .milliseconds(130))
                }
            } catch { }
        }
    }

}
struct ControllerLibraryView: View {
    @State private var input = HubControllerInput.shared
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
    var body: some View {
        let visibleGames = games
        let selectedGame = visibleGames.indices.contains(selection) ? visibleGames[selection] : nil
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("PLAY").font(HubTheme.heading(38)).tracking(2)
                Spacer()
                Label(input.connected ? "Controller connected" : "Keyboard ready", systemImage: "gamecontroller")
            }
            TextField("Search games", text: $search).textFieldStyle(.roundedBorder).focused($focus, equals: .search)
                .onSubmit { details = selectedGame != nil; focus = .browsing }
            Text("↑ ↓ Browse · A / Return Details & Play · B / Escape Back · Menu Sidebar · X Favorite · Y Favorites filter")
                .font(.system(size: 16)).foregroundStyle(.secondary)
            if details, let game = selectedGame {
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
                            Text("S · Launch settings").font(.caption).foregroundStyle(.secondary)
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
                            ForEach(Array(visibleGames.enumerated()), id: \.element.id) { position, game in
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
            if visibleGames.isEmpty { ContentUnavailableView("No matching games", systemImage: "gamecontroller", description: Text("Change the filter or add games through Library.")) }
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
            if focus == .search { details = selectedGame != nil; focus = .browsing } else { action("select") }
            return .handled
        }
        .onKeyPress("x") { guard focus != .search else { return .ignored }; action("favorite"); return .handled }
        .onKeyPress("s") { guard focus != .search, details else { return .ignored }; action("settings"); return .handled }
        .onKeyPress("y") { guard focus != .search else { return .ignored }; action("filter"); return .handled }
        .onExitCommand { input.onAction?("back") }
        .onChange(of: search) { _, _ in selection = 0; details = false }
        .sheet(isPresented: $showLaunchSettings) {
            LaunchSettingsView(initialProfileID: detailProfile?.profileID)
        }
        .onAppear {
            input.contentAction = { command in
                if command == "sidebar" { showLaunchSettings = false; return true }
                if command == "back" && !details && !showLaunchSettings { return false }
                action(command); return true
            }
            focus = .browsing
        }
        .onDisappear { input.contentAction = nil }
    }
    private func displayedTarget(for game: SteamGame, record: GameRecord) -> LaunchTarget? {
        game.selectedLaunchTarget
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
        let visibleGames = games
        let currentGame = visibleGames.indices.contains(selection) ? visibleGames[selection] : nil
        switch action {
        case "up": if !details { selection = max(0, selection - 1) }
        case "down": if !details { selection = min(max(0, visibleGames.count - 1), selection + 1) }
        case "select": if details, let game = currentGame { play(game) } else { details = true }
        case "settings": if details, detailProfile != nil { showLaunchSettings = true }
        case "back": details = false
        case "favorite": if let game = currentGame { game.isFavourited.toggle(); GameDataStore.shared.savePreferences(for: game) }
        case "filter": favoritesOnly.toggle(); selection = 0; details = false
        case "left", "right":
            if details, let game = currentGame as? SteamGame, let record = game.record {
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
