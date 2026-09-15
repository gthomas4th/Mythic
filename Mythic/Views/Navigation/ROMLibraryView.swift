import SwiftUI
import UniformTypeIdentifiers

struct ROMSource: Codable, Identifiable {
    var id = UUID()
    var system: String
    var emulator: EmulatorKind
    var root: Data
    var application: Data
    var core: Data?
    var applicationVersion: String?
    var locationHint: String?
    var dolphinPreset: DolphinGraphicsPreset?
    var index = ROMIndex()
    func resolve(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard !stale else { throw GameHubRuntime.RuntimeError.access }
        return url
    }
}
struct ROMLocalCopy: Codable {
    var root: Data
    var selected: Bool
}
@MainActor @Observable final class ROMLibrary {
    static let shared = ROMLibrary()
    var sources: [ROMSource] = [] { didSet { cachedGames = nil } }
    @ObservationIgnored private var cachedGames: Set<Game>?
    var sourcePaths: [UUID: String] = [:]
    @ObservationIgnored private var resolvedRoots: [UUID: URL] = [:]
    @ObservationIgnored private var requestedBookmarks: [UUID: Data] = [:]
    @ObservationIgnored private var resolvingSources: Set<UUID> = []
    var status = "Choose a ROM folder when your files are ready. Steam Deck references remain available separately."
    var scanning = false
    var localCopies: [String: ROMLocalCopy] = [:]
    var downloadingID: String?
    var downloadStatus = ""
    @ObservationIgnored private var downloadTask: Task<URL, Error>?
    private let copiesFile = GameHubRuntime.support.appendingPathComponent("rom-local-copies.json")
    private var scanToken: UUID?
    @ObservationIgnored private var gameCache: [String: ROMGame] = [:]
    private let file = GameHubRuntime.support.appendingPathComponent("rom-sources.json")
    init() {
        if let data = try? Data(contentsOf: copiesFile), let saved = try? JSONDecoder().decode([String: ROMLocalCopy].self, from: data) { localCopies = saved }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ROMSource].self, from: data) { sources = saved }
    }
    var games: Set<Game> {
        let currentSources = sources // Keep source changes observable even when the catalog is cached.
        if let cachedGames { return cachedGames }
        let result = Set(currentSources.flatMap { source in
            // Rendering never resolves a bookmark or contacts a network volume.
            let root = resolvedRoots[source.id] ?? URL(fileURLWithPath: "/unavailable")
            return source.index.entries.map { entry in
                if let existing = gameCache[entry.id], existing.source?.id == source.id, existing.source?.root == source.root, existing.source?.application == source.application, existing.entry?.relativePath == entry.relativePath { return existing as Game }
                let game = ROMGame(source: source, entry: entry, content: root.appendingPathComponent(entry.relativePath))
                game.sourceLocationLabel = source.locationHint
                game.localCopySelected = localCopies[entry.id]?.selected == true
                GameDataStore.shared.restorePreferences(for: game)
                gameCache[entry.id] = game
                return game as Game
            }
        })
        cachedGames = result
        refreshSourceLocations()
        return result
    }
    func refreshSourceLocations(force: Bool = false) {
        if force { requestedBookmarks = [:] }
        for source in sources where requestedBookmarks[source.id] != source.root && !resolvingSources.contains(source.id) {
            requestedBookmarks[source.id] = source.root
            resolvingSources.insert(source.id)
            Task {
                defer { resolvingSources.remove(source.id) }
                let result = await Task.detached(priority: .utility) { () -> (URL?, String?) in
                    guard let root = try? source.resolve(source.root) else { return (nil, nil) }
                    let access = root.startAccessingSecurityScopedResource()
                    defer { if access { root.stopAccessingSecurityScopedResource() } }
                    let local = (try? root.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal
                    return (root, local.map { $0 ? "Local" : "Server" })
                }.value
                guard let index = sources.firstIndex(where: { $0.id == source.id && $0.root == source.root }) else { return }
                sourcePaths[source.id] = result.0?.path ?? "Source unavailable — reconnect its drive or share."
                if let root = result.0 { resolvedRoots[source.id] = root }
                for game in gameCache.values where game.source?.id == source.id {
                    game.sourceLocationLabel = result.1 ?? source.locationHint
                    if let root = result.0, let entry = game.entry {
                        game.installationState = .installed(location: root.appendingPathComponent(entry.relativePath), platform: .macOS)
                    }
                }
                if let label = result.1, sources[index].locationHint != label {
                    sources[index].locationHint = label
                    try? save()
                }
            }
        }
    }
    func selectLocal(_ selected: Bool, gameID: String) {
        let previous = localCopies
        localCopies[gameID]?.selected = selected
        do { try saveCopies(); gameCache[gameID]?.localCopySelected = selected } catch { localCopies = previous; downloadStatus = "Could not save the play location." }
    }
    private func saveCopies() throws {
        try FileManager.default.createDirectory(at: copiesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(localCopies).write(to: copiesFile, options: .atomic)
    }
    func cancelDownload() { downloadTask?.cancel() }
    func download(_ game: ROMGame) {
        guard downloadingID == nil, let source = game.source, let entry = game.entry else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.message = "Choose a local folder for this ROM. Its server copy will be kept."
        panel.prompt = "Download here"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let root = try source.resolve(source.root)
            guard (try destination.resourceValues(forKeys: [.volumeIsLocalKey])).volumeIsLocal == true else {
                downloadStatus = "Choose a folder on this Mac or an attached drive."; return
            }
            let sourceAccess = root.startAccessingSecurityScopedResource()
            let destinationAccess = destination.startAccessingSecurityScopedResource()
            downloadingID = game.id; downloadStatus = "Preparing download…"
            let gameID = game.id
            let task = Task.detached(priority: .utility) {
                try ROMLocalDownload.copy(content: root.appendingPathComponent(entry.relativePath), sourceRoot: root, destinationParent: destination) { received, total in
                    Task { @MainActor in
                        guard self.downloadingID == gameID else { return }
                        self.downloadStatus = String(format: "Downloading · %.2f / %.2f GB", Double(received) / 1_000_000_000, Double(total) / 1_000_000_000)
                    }
                }
            }
            downloadTask = task
            Task {
                defer {
                    downloadingID = nil; downloadTask = nil
                    if sourceAccess { root.stopAccessingSecurityScopedResource() }
                    if destinationAccess { destination.stopAccessingSecurityScopedResource() }
                }
                do {
                    let local = try await task.value
                    let previous = localCopies
                    localCopies[game.id] = ROMLocalCopy(root: try local.bookmarkData(options: .withSecurityScope), selected: true)
                    do { try saveCopies() } catch { localCopies = previous; throw error }
                    game.localCopySelected = true
                    downloadStatus = "Download verified. Play now uses the Local copy."
                } catch is CancellationError { downloadStatus = "Download cancelled. The server copy is unchanged." }
                catch { downloadStatus = "Download could not finish: " + error.localizedDescription }
            }
        } catch { downloadStatus = "The server ROM could not be opened: " + error.localizedDescription }
    }
    func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(sources).write(to: file, options: .atomic)
    }
    func add(system: String, emulator: EmulatorKind, dolphinPreset: DolphinGraphicsPreset = .emulatorSettings) {
        guard CompatibilityProfile.safeID(system) else { status = "Enter a short system ID such as ps1, ps2 or snes."; return }
        let rootPanel = NSOpenPanel(); rootPanel.canChooseDirectories = true; rootPanel.canChooseFiles = false
        rootPanel.message = "Choose the folder containing your own games for this system."
        guard rootPanel.runModal() == .OK, let root = rootPanel.url else { return }
        let appPanel = NSOpenPanel()
        appPanel.canChooseFiles = true; appPanel.canChooseDirectories = false
        appPanel.allowedContentTypes = [.application]
        appPanel.message = "Choose the installed emulator application."
        guard appPanel.runModal() == .OK, let app = appPanel.url else { return }
        do {
            let installation = try EmulatorApplicationInfo.inspect(application: app)
            var core: Data?
            if emulator == .retroArch {
                let corePanel = NSOpenPanel(); corePanel.message = "Choose the installed RetroArch core (.dylib) for this system."
                guard corePanel.runModal() == .OK, let url = corePanel.url, url.pathExtension == "dylib" else { return }
                core = try url.bookmarkData(options: .withSecurityScope)
            }
            let previous = sources
            sources.append(ROMSource(system: system, emulator: emulator, root: try root.bookmarkData(options: .withSecurityScope),
                application: try app.bookmarkData(options: .withSecurityScope), core: core,
                applicationVersion: installation.version, dolphinPreset: emulator == .dolphin ? dolphinPreset : nil))
            do { try save() } catch { sources = previous; throw error }
            scan()
        } catch let error as ROMError { status = error.localizedDescription } catch { status = "Could not save folder access. Your existing sources are unchanged." }
    }
    func setDolphinPreset(_ preset: DolphinGraphicsPreset, sourceID: UUID) {
        guard let position = sources.firstIndex(where: { $0.id == sourceID && $0.emulator == .dolphin }) else { return }
        let previous = sources[position].dolphinPreset
        sources[position].dolphinPreset = preset
        do {
            try save()
            gameCache = gameCache.filter { $0.value.source?.id != sourceID }
            status = "Graphics preset saved. It will apply the next time you launch a game from this source."
        } catch {
            sources[position].dolphinPreset = previous
            status = "Could not save the graphics preset. The previous setting was kept."
        }
    }
    func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            defer { scanning = false; scanToken = nil }
            var count = 0
            for position in sources.indices {
                do {
                    let source = sources[position]
                    let token = UUID(); scanToken = token
                    status = "Scanning \(source.system)… Unchanged files reuse their saved hashes."
                    let root = try source.resolve(source.root)
                    let access = root.startAccessingSecurityScopedResource()
                    defer { if access { root.stopAccessingSecurityScopedResource() } }
                    let index = try await Task.detached(priority: .utility) {
                        var index = source.index
                        try index.scan(root: root, system: source.system) { progress in
                            Task { @MainActor in
                                guard self.scanToken == token, self.scanning else { return }
                                let read = Double(progress.bytesRead) / 1_000_000_000
                                let total = Double(progress.totalBytes) / 1_000_000_000
                                self.status = String(format: "Reading %@ · %.2f / %.2f GB. Games stay in their source folder.", progress.title, read, total)
                            }
                        }
                        return index
                    }.value
                    sources[position].index = index; count += index.entries.count
                } catch { status = "A ROM folder or disc part is unavailable. Existing entries were kept."; return }
            }
            do { try save(); status = "Indexed \(count) games. Configure BIOS or firmware in each emulator before first play." } catch { status = "The scan finished but its index could not be saved." }
        }
    }
}
@Observable final class ROMGame: Game {
    var localCopySelected = false
    var sourceLocationLabel: String?
    let source: ROMSource?
    let entry: ROMEntry?
    override var storefront: Storefront? { .local }
    override var sourceLabel: String { locationLabel ?? "ROM" }
    override var typeLabel: String? { "ROM" }
    override var locationLabel: String? {
        if localCopySelected { return "Local" }
        return sourceLocationLabel
    }
    override var supportsFileManagement: Bool { false }
    override var supportsLaunchArguments: Bool { false }
    init(source: ROMSource, entry: ROMEntry, content: URL) {
        self.source = source; self.entry = entry
        super.init(id: entry.id, title: entry.title, installationState: .installed(location: content, platform: .macOS))
    }
    required init(from decoder: any Decoder) throws { source = nil; entry = nil; try super.init(from: decoder) }
    @MainActor override func _launch() async throws {
        guard let source, let entry else { throw ROMError.invalid }
        let root: URL
        if let copy = ROMLibrary.shared.localCopies[id], copy.selected {
            var stale = false
            root = try URL(resolvingBookmarkData: copy.root, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            guard !stale else { throw ROMError.missingPart }
        } else { root = try source.resolve(source.root) }
        let app = try source.resolve(source.application)
        let core = try source.core.map { try source.resolve($0) }
        let urls = [root, app] + [core].compactMap { $0 }
        let access = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (index, url) in urls.enumerated() where access[index] { url.stopAccessingSecurityScopedResource() } }
        let content = root.appendingPathComponent(entry.relativePath).resolvingSymlinksInPath()
        _ = try ROMIndex.parts(of: content, root: root)
        _ = try EmulatorApplicationInfo.inspect(application: app)
        guard core.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? true else { throw ROMError.coreMissing }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = try EmulatorCommand.arguments(kind: source.emulator, content: content, core: core, dolphinPreset: source.dolphinPreset ?? .emulatorSettings)
        try await NSWorkspace.shared.openApplication(at: app, configuration: config)
    }
}
struct ROMLibraryView: View {
    @Bindable private var store = ROMLibrary.shared
    @State private var system = "ps1"
    @State private var emulator = EmulatorKind.duckStation
    @State private var deckPresented = false
    @State private var dolphinPreset = DolphinGraphicsPreset.metal1080
    var body: some View {
        Form {
            Section("Add a system") {
                TextField("System ID", text: $system)
                Picker("Emulator", selection: $emulator) {
                    ForEach(EmulatorKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if emulator == .dolphin {
                    Picker("Graphics", selection: $dolphinPreset) {
                        ForEach(DolphinGraphicsPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Text("Metal 3× is a starting point for this Mac. Lower to native resolution if a game struggles. The preset applies only when launching from Game Hub.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Choose ROM folder and emulator…") { store.add(system: system, emulator: emulator, dolphinPreset: dolphinPreset) }.disabled(store.scanning)
                Text("Use your existing emulator configuration. BIOS and firmware must be supplied separately. ROMs stay on their source unless you choose Download locally.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Sources") {
                ForEach(store.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(source.system, value: "\(source.index.entries.count) games · \(source.emulator.displayName)")
                        Text(store.sourcePaths[source.id] ?? "Checking source…")
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Version when added: \(source.applicationVersion ?? "Not checked")")
                            .font(.caption).foregroundStyle(.secondary)
                        if source.emulator == .dolphin {
                            Picker("Graphics", selection: Binding(
                                get: { source.dolphinPreset ?? .emulatorSettings },
                                set: { store.setDolphinPreset($0, sourceID: source.id) }
                            )) {
                                ForEach(DolphinGraphicsPreset.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                }
                Button("Rescan folders") { store.scan() }.disabled(store.scanning || store.sources.isEmpty)
                if store.scanning { ProgressView("Scanning ROM sources…") }
                Text(store.status).font(.callout)
            }
            Section("Steam Deck") {
                Button("Import or browse Deck references") { deckPresented = true }
                Text("Deck-only paths remain labelled unavailable on this Mac until the real files are copied.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).navigationTitle("ROM Library")
        .task { store.refreshSourceLocations(force: true) }
        .sheet(isPresented: $deckPresented) { SteamDeckLibraryView() }
    }
}
