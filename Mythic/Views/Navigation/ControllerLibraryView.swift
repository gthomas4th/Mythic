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
            for button in [pad.dpad.up, pad.dpad.down, pad.dpad.left, pad.dpad.right, pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY] {
                button.pressedChangedHandler = nil
            }
        }
    }
    private func bind() {
        connected = !GCController.controllers().isEmpty
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            for (button, action) in [(pad.dpad.up, "up"), (pad.dpad.down, "down"), (pad.dpad.left, "left"),
                (pad.dpad.right, "right"), (pad.buttonA, "select"), (pad.buttonB, "back"), (pad.buttonX, "favorite"), (pad.buttonY, "filter")] {
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
    @State private var selection = 0
    @State private var details = false
    @State private var favoritesOnly = false
    @State private var message = ""
    @State private var search = ""
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
                Text("Play").font(.largeTitle.bold())
                Spacer()
                Label(input.connected ? "Controller connected" : "Keyboard ready", systemImage: "gamecontroller")
            }
            TextField("Search games", text: $search).textFieldStyle(.roundedBorder).focused($focus, equals: .search)
                .onSubmit { details = selected != nil; focus = .browsing }
            Text("↑ ↓ Browse · A / Return Details & Play · B / Escape Back · X Favorite · Y Favorites filter")
                .font(.callout).foregroundStyle(.secondary)
            if details, let game = selected {
                Text(game.title).font(.title.bold())
                if let steam = game as? SteamGame, let record = steam.record {
                    let kind = LaunchResolver.resolve(record.launchTargets, preferredID: steam.preferredTargetID)?.kind
                    Text(kind == .wineSteam ? "Windows Steam · pinned profile" : (kind == .moonlight ? "Home PC" : (kind == .nativeMac ? "Native Mac" : "Unavailable")))
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
                                        Text(game.title).font(.title3)
                                        Spacer()
                                        Text(game.storefront?.description ?? "Game").foregroundStyle(.secondary)
                                    }.padding(16).frame(maxWidth: .infinity)
                                        .background(selection == position ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
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
        .padding(24).navigationTitle("Controller Library")
        .focusable()
        .focused($focus, equals: .browsing)
        .onMoveCommand { direction in if focus != .search { action(String(describing: direction)) } }
        .onKeyPress(.return) {
            if focus == .search { details = selected != nil; focus = .browsing } else { action("select") }
            return .handled
        }
        .onKeyPress("x") { guard focus != .search else { return .ignored }; action("favorite"); return .handled }
        .onKeyPress("y") { guard focus != .search else { return .ignored }; action("filter"); return .handled }
        .onExitCommand { action("back") }
        .onChange(of: search) { _, _ in selection = 0; details = false }
        .onAppear { input.onAction = action; input.start(); focus = .browsing }
        .onDisappear { input.stop(); input.onAction = nil }
    }
    private func action(_ action: String) {
        switch action {
        case "up": if !details { selection = max(0, selection - 1) }
        case "down": if !details { selection = min(max(0, games.count - 1), selection + 1) }
        case "select": if details, let game = selected { play(game) } else { details = true }
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
