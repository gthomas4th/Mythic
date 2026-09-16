import SwiftUI
import AVKit
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
    private var sessionQuitTask: Task<Void, Never>?
    private var lastAction = ""
    private var lastActionTime = Date.distantPast
    private let duplicateWindow: TimeInterval = 0.09
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
        sessionQuitTask?.cancel(); sessionQuitTask = nil
        lastAction = ""; lastActionTime = .distantPast
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
        connected = GCController.controllers().contains { $0.extendedGamepad != nil }
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            pad.leftThumbstick.valueChangedHandler = { [weak self] _, axisX, axisY in
                let direction: String? = max(abs(axisX), abs(axisY)) < 0.65 ? nil : (abs(axisY) >= abs(axisX) ? (axisY > 0 ? "up" : "down") : (axisX > 0 ? "right" : "left"))
                Task { @MainActor in self?.moveStick(direction) }
            }
            for (button, action) in [(pad.dpad.up, "up"), (pad.dpad.down, "down"), (pad.dpad.left, "left"),
                (pad.dpad.right, "right"), (pad.buttonA, "select"), (pad.buttonB, "back"), (pad.buttonX, "options"), (pad.buttonY, "filter"), (pad.buttonMenu, "settings")] {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    let sessionShortcutPressed = pad.buttonMenu.isPressed && pad.buttonB.isPressed
                    Task { @MainActor in
                        guard NSApp.isActive else {
                            self?.updateSessionShortcut(sessionShortcutPressed)
                            return
                        }
                        self?.updateSessionShortcut(false)
                        guard pressed else { return }
                        self?.dispatch(action)
                    }
                }
            }
        }
    }
    private func updateSessionShortcut(_ pressed: Bool) {
        guard pressed else {
            sessionQuitTask?.cancel(); sessionQuitTask = nil
            return
        }
        guard sessionQuitTask == nil, EmulatorSessionCoordinator.shared.hasActiveSession else { return }
        sessionQuitTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(800))
                self?.sessionQuitTask = nil
                await EmulatorSessionCoordinator.shared.quitActiveSession()
            } catch { }
        }
    }
    private func moveStick(_ direction: String?) {
        if direction == nil {
            stickDirection = nil
            stickTask?.cancel(); stickTask = nil
            return
        }
        // Lock one axis until the stick returns to center. A near-diagonal gesture
        // can otherwise alternate between axes and advance more than once.
        guard stickDirection == nil, let direction else { return }
        stickDirection = direction
        stickTask?.cancel()
        if NSApp.isActive { dispatch(direction) }
        stickTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                while !Task.isCancelled {
                    if NSApp.isActive { self?.dispatch(direction) }
                    try await Task.sleep(for: .milliseconds(130))
                }
            } catch { }
        }
    }
    private func dispatch(_ action: String) {
        let now = Date()
        // Multi-interface controllers can report one physical press several times.
        // Collapse simultaneous duplicates while retaining deliberate taps and repeat.
        guard action != lastAction || now.timeIntervalSince(lastActionTime) >= duplicateWindow else { return }
        lastAction = action; lastActionTime = now
        onAction?(action)
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
    @State private var keyMonitor: Any?
    private enum Focus: Hashable { case search, browsing }
    @FocusState private var focus: Focus?
    private var games: [Game] {
        GameDataStore.shared.displayLibrary.filter {
            (!favoritesOnly || $0.isFavourited) && (search.isEmpty || $0.title.localizedStandardContains(search))
        }.sorted {
            let left = $0 is ROMGame ? ROMTitle.sortKeyForDisplayName($0.title) : $0.title
            let right = $1 is ROMGame ? ROMTitle.sortKeyForDisplayName($1.title) : $1.title
            return left.localizedStandardCompare(right) == .orderedAscending
        }
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
                HubControllerHints(actions: [("Move", "Browse"), ("A", "Play"), ("X", "Options"), ("Y", "Favorites"), ("B", "Back"), ("Menu", "Sidebar")])
            } else { Text("↑ ↓ Browse · Return Details / Play · Escape Back").font(.system(size: 16)) }
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
        .onMoveCommand { direction in if !input.connected && focus != .search { action(String(describing: direction)) } }
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
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard HubGameOptions.shared.game == nil else { return event }
                if event.keyCode == 53 {
                    if details { details = false } else { input.onAction?("back") }
                    return nil
                }
                if [36, 76].contains(event.keyCode), focus != .search {
                    if details {
                        if let game = selectedGame { play(game) }
                    } else if selectedGame != nil {
                        details = true
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            input.clearContent("controller")
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }
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
        case "select": if let game = currentGame { play(game) }
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
    var motionEnabled = UserDefaults.standard.object(forKey: "hubMotionBackgrounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(motionEnabled, forKey: "hubMotionBackgrounds") }
    }
    var game: Game?
    var row = 0
    var editor: String?
    var draft = ""
    var key = 0
    var keyboardMode = 0
    var message = ""
    private let file: URL
    private var edits: [String: [String: String]] = [:]
    var keyboardRows: [[String]] {
        switch keyboardMode {
        case 1:
            [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
             ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
             ["Shift", "Z", "X", "C", "V", "B", "N", "M", "⌫"],
             ["123", "-", "_", "'", "Space", ".", "Clear"]]
        case 2:
            [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
             ["-", "_", ":", "/", "?", "&", "=", "+", "#"],
             ["@", "(", ")", "[", "]", "%", "'", "\"", "⌫"],
             ["ABC", "Space", ".", "Clear"]]
        default:
            [["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
             ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
             ["Shift", "z", "x", "c", "v", "b", "n", "m", "⌫"],
             ["123", "-", "_", "'", "Space", ".", "Clear"]]
        }
    }
    var keys: [String] { keyboardRows.flatMap { $0 } }
    var selectedKey: String { keys.indices.contains(key) ? keys[key] : "q" }
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
        return ["Play", game.isFavourited ? "Remove favorite" : "Add favorite", "Play location: \(game.locationLabel ?? "Unavailable")", "Edit title", "Edit artwork URL", "Close"]
    }
    func action(_ action: String) -> Bool {
        guard let game else { return false }
        if action == "settings" || action == "sidebar" { self.game = nil; return false }
        if editor != nil {
            switch action {
            case "back": editor = nil
            case "up", "down", "left", "right": moveKey(action)
            case "select": typeKey(selectedKey)
            case "options": if !draft.isEmpty { draft.removeLast() }
            case "filter": saveEdit()
            default: break
            }
            return true
        }
        switch action {
        case "filter": motionEnabled.toggle()
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
        else if character == "Space" { draft += " " }
        else if character == "Shift" { keyboardMode = keyboardMode == 1 ? 0 : 1; key = 0 }
        else if character == "123" { keyboardMode = 2; key = 0 }
        else if character == "ABC" { keyboardMode = 0; key = 0 }
        else {
            draft += character
            if keyboardMode == 1 { keyboardMode = 0; key = 0 }
        }
    }
    func moveKey(_ direction: String) {
        let rows = keyboardRows
        var offset = 0
        var position = (row: 0, column: 0)
        for (rowIndex, row) in rows.enumerated() {
            if key < offset + row.count { position = (rowIndex, key - offset); break }
            offset += row.count
        }
        switch direction {
        case "left": position.column = max(0, position.column - 1)
        case "right": position.column = min(rows[position.row].count - 1, position.column + 1)
        case "up": position.row = max(0, position.row - 1); position.column = min(position.column, rows[position.row].count - 1)
        case "down": position.row = min(rows.count - 1, position.row + 1); position.column = min(position.column, rows[position.row].count - 1)
        default: break
        }
        key = rows.prefix(position.row).reduce(0) { $0 + $1.count } + position.column
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
    @State private var imageEmpty = true
    @State private var scene = HubGameScene()
    @State private var toolbarWasVisible: Bool?
    @State private var escapeMonitor: Any?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backdrop.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack {
                                Button { _ = model.action("back") } label: {
                                    if input.connected { HubButtonHint(button: "B", action: "Back") }
                                    else { Label("Back", systemImage: "chevron.left") }
                                }.buttonStyle(.plain)
                                Spacer()
                                if scene.hasVideo {
                                    Button { model.motionEnabled.toggle() } label: {
                                        if input.connected { HubButtonHint(button: "Y", action: model.motionEnabled ? "Still image" : "Moving scene") }
                                        else { Label(model.motionEnabled ? "Still image" : "Moving scene", systemImage: "play.rectangle") }
                                    }.buttonStyle(.plain)
                                }
                                if let game = model.game {
                                    GameCard.LegacyMenuView(game: .constant(game)).help("Advanced settings and ROM downloads")
                                }
                            }
                            if let editor = model.editor {
                                editorPanel(editor).padding(24)
                                    .background(.black.opacity(0.72), in: .rect(cornerRadius: 16))
                                    .frame(maxWidth: 740).frame(maxWidth: .infinity)
                            } else if let game = model.game {
                                Spacer(minLength: max(24, geometry.size.height * 0.12))
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(game.title.uppercased())
                                        .font(HubTheme.heading(game.title.count > 54 ? 36 : 52)).tracking(2)
                                        .lineLimit(3).minimumScaleFactor(0.72).shadow(color: .black.opacity(0.6), radius: 12)
                                        .frame(maxWidth: 850, alignment: .leading)
                                    HStack(spacing: 16) {
                                        Text(game.locationLabel ?? "Unavailable")
                                        if let rom = game as? ROMGame, let source = rom.source {
                                            HStack(spacing: 6) {
                                                HubSystemMark(system: source.system, size: 18)
                                                Text(HubSystemMark.shortName(for: source.system))
                                            }
                                        }
                                        if let played = game.lastLaunched { Text("Last played " + played.formatted(date: .abbreviated, time: .omitted)) }
                                    }.font(.system(size: 15)).foregroundStyle(.white.opacity(0.8))
                                    if game is ROMGame {
                                        Text("Full screen · Escape or hold Menu + B exits · Pause-menu Quit returns here")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.86))
                                    }
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(model.labels.enumerated()), id: \.offset) { item in
                                        option(item.offset, label: item.element).id(item.offset)
                                    }
                                }.padding(10).frame(maxWidth: 390)
                                    .background(.black.opacity(0.28), in: .rect(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14), lineWidth: 1))
                                if input.connected {
                                    HubControllerHints(actions: [("Move", "Choose"), ("A", "Select"), ("B", "Back")])
                                }
                            }
                            if !model.message.isEmpty {
                                Text(model.message).font(.system(size: 17)).padding(12)
                                    .background(.black.opacity(0.7), in: .rect(cornerRadius: 8))
                            }
                        }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    }.onChange(of: model.row) { _, row in proxy.scrollTo(row, anchor: .bottom) }
                }
            }.foregroundStyle(.white)
        }.environment(\.colorScheme, .dark)
            .onAppear {
                if let toolbar = NSApp.keyWindow?.toolbar {
                    toolbarWasVisible = toolbar.isVisible
                    toolbar.isVisible = false
                }
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53 else { return event }
                    _ = model.action("back")
                    return nil
                }
            }
            .onDisappear {
                if let toolbarWasVisible { NSApp.keyWindow?.toolbar?.isVisible = toolbarWasVisible }
                if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
            }
            .task(id: model.game?.id) {
                await scene.load(model.game)
                updateScene()
            }
            .onChange(of: model.motionEnabled) { _, _ in updateScene() }
            .onChange(of: model.editor) { _, _ in updateScene() }
            .onChange(of: model.game?.isLaunching) { _, _ in updateScene() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in scene.setPlaying(false) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in updateScene() }
            .onDisappear { scene.stop() }
            .onExitCommand { _ = model.action("back") }
    }
    private func updateScene() {
        scene.setPlaying(model.motionEnabled && model.editor == nil && model.game?.isLaunching != true && NSApp.isActive)
    }
    private var backdrop: some View {
        GeometryReader { geometry in
            ZStack {
                HubTheme.blue
                if let game = model.game {
                    let url = scene.poster ?? game.horizontalImageURL ?? game.verticalImageURL
                    if url != nil, game is ROMGame || (!(game is ROMGame) && scene.poster == nil && game.horizontalImageURL == nil) {
                        // Portrait storefront art becomes a full-bleed composition: a
                        // blurred fill behind the intact cover, never a stretched image.
                        ZStack {
                            GameImageCard(game: game, url: url, isImageEmpty: $imageEmpty,
                                withBlur: false, contentMode: .fill)
                                .scaleEffect(1.06).blur(radius: 28)
                            Color.black.opacity(0.28)
                            GameImageCard(game: game, url: url, isImageEmpty: $imageEmpty,
                                withBlur: false, contentMode: .fit)
                                .padding(.vertical, 20)
                                .shadow(color: .black.opacity(0.55), radius: 18)
                        }.clipped()
                    } else {
                        GameImageCard(game: game, url: url, isImageEmpty: $imageEmpty, withBlur: false,
                            contentMode: .fill, romArtworkKind: game is ROMGame ? .scene : .boxart)
                    }
                }
                if let player = scene.player, model.motionEnabled {
                    HubScenePlayer(player: player).allowsHitTesting(false)
                }
                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0.15), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    private func option(_ index: Int, label: String) -> some View {
        Button { model.row = index; model.activate() } label: {
            HStack(spacing: 12) {
                if input.connected && index == 0 { HubButtonHint(button: "A", action: "Play") }
                else { Text(label).font(.system(size: 17, weight: .medium)) }
                Spacer(minLength: 8)
                if input.connected && model.row == index && index != 0 { HubButtonHint(button: "A", action: "") }
            }.frame(minHeight: 28).padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(.white)
                .background(model.row == index ? .white.opacity(0.2) : .clear, in: .rect(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.row == index ? HubTheme.yellow.opacity(0.9) : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
    private func editorPanel(_ editor: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("Edit \(editor)").font(.title2)
                TextField(editor, text: $model.draft).textFieldStyle(.roundedBorder)
                if input.connected { HubControllerHints(actions: [("Move", "Choose key"), ("A", "Type"), ("X", "Delete"), ("Y", "Save"), ("B", "Cancel")]) }
                VStack(spacing: 8) {
                    ForEach(Array(model.keyboardRows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 8) {
                            ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, character in
                                let index = model.keyboardRows.prefix(rowIndex).reduce(0) { $0 + $1.count } + columnIndex
                                Button(character) { model.key = index; model.typeKey(character) }
                                    .frame(maxWidth: character == "Space" ? 150 : .infinity, minHeight: 38)
                                    .foregroundStyle(.black)
                                    .background(model.key == index ? HubTheme.yellow : HubTheme.panel, in: .rect(cornerRadius: 5))
                                    .buttonStyle(.plain)
                            }
                        }
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
        }.font(.system(size: 17))
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


@MainActor @Observable final class HubGameScene {
    var poster: URL?
    var player: AVPlayer?
    var hasVideo = false
    private var videoURL: URL?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var playing = false
    @ObservationIgnored private var generation = UUID()
    private static var cache: [String: (URL?, URL?)] = [:]
    private static func mediaURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              let host = url.host, host.hasSuffix(".steamstatic.com") else { return nil }
        return url
    }
    func load(_ game: Game?) async {
        stop(); poster = nil; hasVideo = false; videoURL = nil
        let token = UUID(); generation = token
        guard let steam = game as? SteamGame, let appID = steam.record?.id.externalID,
              UInt32(appID) != nil else { return }
        if let cached = Self.cache[appID] {
            poster = cached.0; videoURL = cached.1; hasVideo = videoURL != nil; return
        }
        do {
            let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=english")!
            var request = URLRequest(url: url); request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, generation == token,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json[appID] as? [String: Any], let info = result["data"] as? [String: Any] else { return }
            let shots = info["screenshots"] as? [[String: Any]]
            let movies = info["movies"] as? [[String: Any]]
            poster = Self.mediaURL(shots?.first?["path_full"] as? String)
            videoURL = movies?.compactMap { Self.mediaURL($0["hls_h264"] as? String) ?? Self.mediaURL(($0["mp4"] as? [String: String])?["480"]) }.first
            hasVideo = videoURL != nil
            Self.cache[appID] = (poster, videoURL)
        } catch { /* Keep the existing artwork when offline. */ }
    }
    func setPlaying(_ enabled: Bool) {
        playing = enabled
        guard enabled, let videoURL else { player?.pause(); return }
        if player == nil {
            let item = AVPlayerItem(url: videoURL)
            item.preferredMaximumResolution = CGSize(width: 1280, height: 720)
            item.preferredPeakBitRate = 2_500_000
            item.preferredForwardBufferDuration = 5
            let created = AVPlayer(playerItem: item); created.isMuted = true
            player = created
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.playing else { return }
                    await self.player?.seek(to: .zero)
                    if self.playing { self.player?.play() }
                }
            }
        }
        player?.play()
    }
    func stop() {
        generation = UUID(); playing = false
        player?.pause(); player?.replaceCurrentItem(with: nil); player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

struct HubScenePlayer: NSViewRepresentable {
    let player: AVPlayer
    final class Coordinator {
        var readiness: NSKeyValueObservation?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.alphaValue = 0
        context.coordinator.readiness = view.observe(\.isReadyForDisplay, options: [.initial, .new]) { view, _ in
            DispatchQueue.main.async { view.alphaValue = view.isReadyForDisplay ? 1 : 0 }
        }
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.readiness?.invalidate(); coordinator.readiness = nil; view.player = nil
    }
}
