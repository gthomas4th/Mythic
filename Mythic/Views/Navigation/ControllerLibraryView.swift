import SwiftUI
@preconcurrency import GameController

@MainActor @Observable final class HubControllerInput {
    static let shared = HubControllerInput()
    var connected = false
    var contentFocused = false
    var contentAction: ((String) -> Bool)?
    private(set) var contentOwner = ""
    func setContent(_ owner: String, action: @escaping (String) -> Bool) {
        contentOwner = owner; contentAction = action
    }
    func clearContent(_ owner: String) {
        guard contentOwner == owner else { return }
        contentOwner = ""; contentAction = nil
    }
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
                (pad.dpad.right, "right"), (pad.buttonA, "select"), (pad.buttonB, "back"), (pad.buttonX, "options"), (pad.buttonY, "filter"), (pad.buttonMenu, "settings")] {
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
            if input.connected {
                HubControllerHints(actions: [("Move", "Browse"), ("A", details ? "Play" : "Details"), ("X", "Options"), ("Y", "Favourites"), ("B", "Back"), ("Menu", "Sidebar")])
            } else { Text("↑ ↓ Browse · Return Details & Play · Escape Back").font(.system(size: 16)) }
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
                                        if input.connected && input.contentFocused && selection == position { HubButtonHint(button: "X", action: "Options") }
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
        .onKeyPress("x") { guard focus != .search else { return .ignored }; action("options"); return .handled }
        .onKeyPress("s") { guard focus != .search, details else { return .ignored }; action("settings"); return .handled }
        .onKeyPress("y") { guard focus != .search else { return .ignored }; action("filter"); return .handled }
        .onExitCommand { input.onAction?("back") }
        .onChange(of: search) { _, _ in selection = 0; details = false }
        .sheet(isPresented: $showLaunchSettings) {
            LaunchSettingsView(initialProfileID: detailProfile?.profileID)
        }
        .onAppear {
            input.setContent("controller") { command in
                if command == "sidebar" { showLaunchSettings = false; return true }
                if command == "back" && !details && !showLaunchSettings { return false }
                action(command); return true
            }
            focus = .browsing
        }
        .onDisappear { input.clearContent("controller") }
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
        case "options": if let game = currentGame { HubGameOptions.shared.open(game) }
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


@MainActor @Observable final class HubGameOptions {
    static let shared = HubGameOptions()
    var game: Game?
    var row = 0
    var editor: String?
    var draft = ""
    var key = 0
    var message = ""
    private let file: URL
    private var edits: [String: [String: String]] = [:]
    let keys = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:/.-_?=&%+# ").map(String.init) + ["⌫", "Clear"]
    init(file: URL = GameHubRuntime.support.appendingPathComponent("game-display-edits.json")) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: [String: String]].self, from: data) { edits = saved }
    }
    private func identity(_ game: Game) -> String {
        let provider: String
        switch game.storefront {
        case .steam: provider = "steam"
        case .epicGames: provider = "epic"
        default: provider = "local"
        }
        return "\(provider):\(game.id)"
    }
    func apply(to game: Game) {
        guard let saved = edits[identity(game)] else { return }
        if let title = saved["Title"] { game.title = title }
        if let artwork = saved["Artwork URL"] { game._verticalImageURL = URL(string: artwork) }
    }
    func open(_ game: Game) { self.game = game; row = 0; editor = nil; message = "" }
    var labels: [String] {
        guard let game else { return [] }
        return ["Play", game.isFavourited ? "Remove favourite" : "Add favourite", "Play location: \(game.locationLabel ?? "Unavailable")", "Edit title", "Edit artwork URL", "Close"]
    }
    func action(_ action: String) -> Bool {
        guard let game else { return false }
        if action == "settings" || action == "sidebar" { self.game = nil; return false }
        if editor != nil {
            switch action {
            case "back": editor = nil
            case "up": key = max(0, key - 10)
            case "down": key = min(keys.count - 1, key + 10)
            case "left": key = max(0, key - 1)
            case "right": key = min(keys.count - 1, key + 1)
            case "select": typeKey(keys[key])
            case "options": if !draft.isEmpty { draft.removeLast() }
            case "filter": saveEdit()
            default: break
            }
            return true
        }
        switch action {
        case "back": self.game = nil
        case "up": row = max(0, row - 1)
        case "down": row = min(labels.count - 1, row + 1)
        case "left", "right": if row == 2 { changeLocation(game) }
        case "select": activate()
        default: break
        }
        return true
    }
    func typeKey(_ character: String) {
        if character == "Clear" { draft = "" }
        else if character == "⌫" { if !draft.isEmpty { draft.removeLast() } }
        else { draft += character }
    }
    func activate() {
        guard let game else { return }
        switch row {
        case 0:
            guard game.canPlayFromLocation else { message = "This game is unavailable at its selected location."; return }
            Task { do { try await game.launch(); self.game = nil } catch { message = error.localizedDescription } }
        case 1: game.isFavourited.toggle(); GameDataStore.shared.savePreferences(for: game)
        case 2: changeLocation(game)
        case 3: editor = "Title"; draft = game.title; key = 0
        case 4: editor = "Artwork URL"; draft = game._verticalImageURL?.absoluteString ?? ""; key = 0
        default: self.game = nil
        }
    }
    private func changeLocation(_ game: Game) {
        if let steam = game as? SteamGame, let targets = steam.record?.launchTargets, targets.count > 1 {
            let index = targets.firstIndex { $0.id == steam.selectedLaunchTarget?.id } ?? 0
            steam.preferredTargetID = targets[(index + 1) % targets.count].id
            GameDataStore.shared.savePreferences(for: steam)
        } else if let copy = ROMLibrary.shared.localCopies[game.id] {
            ROMLibrary.shared.selectLocal(!copy.selected, gameID: game.id)
        } else { message = "This game has one configured play location." }
    }
    func saveEdit() {
        guard let game, let editor else { return }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { message = "Enter a value before saving."; return }
        if editor == "Artwork URL" {
            guard let url = URL(string: value), ["https", "http"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else { message = "Enter an HTTP or HTTPS image URL."; return }
        }
        var saved = edits
        saved[identity(game), default: [:]][editor] = value
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: file, options: .atomic)
            edits = saved; apply(to: game); self.editor = nil; message = "Saved."
        } catch { message = "Could not save: " + error.localizedDescription }
    }
}

struct HubGameOptionsView: View {
    @Bindable var model = HubGameOptions.shared
    @State private var input = HubControllerInput.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.game?.title ?? "Game options").font(HubTheme.heading(27)).lineLimit(2)
            if let editor = model.editor {
                Text("Edit \(editor)").font(.title2)
                TextField(editor, text: $model.draft).textFieldStyle(.roundedBorder)
                if input.connected { HubControllerHints(actions: [("Move", "Choose key"), ("A", "Type"), ("X", "Delete"), ("Y", "Save"), ("B", "Cancel")]) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 8) {
                    ForEach(model.keys.indices, id: \.self) { index in
                        Button(model.keys[index] == " " ? "Space" : model.keys[index]) { model.key = index; model.typeKey(model.keys[index]) }
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(model.key == index ? HubTheme.yellow : HubTheme.panel, in: .rect(cornerRadius: 5))
                            .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button { model.editor = nil } label: {
                        if input.connected { HubButtonHint(button: "B", action: "Cancel") } else { Text("Cancel") }
                    }
                    Spacer()
                    Button { model.saveEdit() } label: {
                        if input.connected { HubButtonHint(button: "Y", action: "Save") } else { Text("Save") }
                    }
                }
            } else {
                if input.connected { HubControllerHints(actions: [("Move", "Choose option"), ("A", "Open / Apply"), ("B", "Back"), ("Menu", "Sidebar")]) }
                ForEach(model.labels.indices, id: \.self) { index in
                    Button { model.row = index; model.activate() } label: {
                        HStack {
                            Text(model.labels[index])
                            Spacer()
                            if input.connected && model.row == index { HubButtonHint(button: "A", action: index == 3 || index == 4 ? "Edit" : "Apply") }
                        }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).padding(12)
                            .background(model.row == index ? HubTheme.yellow : HubTheme.panel, in: .rect(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            if !model.message.isEmpty { Text(model.message).font(.callout) }
        }.font(.system(size: 17)).padding(24).frame(width: 680).background(HubTheme.canvas)
            .onExitCommand { _ = model.action("back") }
    }
}


/// Button letters match the controller mappings; colour is supplementary to the label.
struct HubButtonHint: View {
    let button: String
    let action: String
    private var tint: Color {
        switch button {
        case "A": HubTheme.green
        case "B": Color(red: 0.85, green: 0.25, blue: 0.25)
        case "X": HubTheme.blue
        case "Y": HubTheme.yellow
        default: HubTheme.panel
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            Group {
                if button == "Move" { Image(systemName: "dpad.fill") }
                else if button == "Menu" { Image(systemName: "line.3.horizontal") }
                else { Text(button).fontWeight(.bold) }
            }
            .font(.system(size: 16)).frame(width: 28, height: 28)
            .foregroundStyle(button == "X" || button == "B" ? Color.white : Color.black)
            .background(tint, in: Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            if !action.isEmpty { Text(action).font(.system(size: 16, weight: .medium)).fixedSize() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(button == "Move" ? "D-pad or left stick" : button) button: \(action)")
    }
}

struct HubControllerHints: View {
    let actions: [(String, String)]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { hints }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) { hints }
        }
    }
    private var hints: some View {
        ForEach(actions.indices, id: \.self) { index in
            HubButtonHint(button: actions[index].0, action: actions[index].1)
        }
    }
}

struct HubSelectedGameHint: View {
    let visible: Bool
    var body: some View {
        if visible {
            HubButtonHint(button: "X", action: "Options")
                .padding(8).background(HubTheme.canvas, in: Capsule()).padding(8)
                .allowsHitTesting(false)
        }
    }
}
