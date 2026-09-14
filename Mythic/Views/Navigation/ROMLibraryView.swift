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
    var dolphinPreset: DolphinGraphicsPreset?
    var index = ROMIndex()
    func resolve(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
        guard !stale else { throw GameHubRuntime.RuntimeError.access }
        return url
    }
}
@MainActor @Observable final class ROMLibrary {
    static let shared = ROMLibrary()
    var sources: [ROMSource] = []
    var status = "Choose a ROM folder when your files are ready. Steam Deck references remain available separately."
    var scanning = false
    private var scanToken: UUID?
    @ObservationIgnored private var gameCache: [String: ROMGame] = [:]
    private let file = GameHubRuntime.support.appendingPathComponent("rom-sources.json")
    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ROMSource].self, from: data) { sources = saved }
    }
    var games: Set<Game> {
        Set(sources.flatMap { source in
            source.index.entries.map { entry in
                if let existing = gameCache[entry.id], existing.source?.id == source.id, existing.entry?.relativePath == entry.relativePath { return existing as Game }
                let root = (try? source.resolve(source.root)) ?? URL(fileURLWithPath: "/unavailable")
                let game = ROMGame(source: source, entry: entry, content: root.appendingPathComponent(entry.relativePath))
                GameDataStore.shared.restorePreferences(for: game)
                gameCache[entry.id] = game
                return game as Game
            }
        })
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
final class ROMGame: Game {
    let source: ROMSource?
    let entry: ROMEntry?
    override var storefront: Storefront? { .local }
    override var supportsFileManagement: Bool { false }
    override var supportsLaunchArguments: Bool { false }
    init(source: ROMSource, entry: ROMEntry, content: URL) {
        self.source = source; self.entry = entry
        super.init(id: entry.id, title: entry.title, installationState: .installed(location: content, platform: .macOS))
    }
    required init(from decoder: any Decoder) throws { source = nil; entry = nil; try super.init(from: decoder) }
    @MainActor override func _launch() async throws {
        guard let source, let entry else { throw ROMError.invalid }
        let root = try source.resolve(source.root), app = try source.resolve(source.application)
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
                Text("Use your existing emulator configuration. BIOS, firmware and game files are never downloaded by the hub.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Sources") {
                ForEach(store.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(source.system, value: "\(source.index.entries.count) games · \(source.emulator.displayName)")
                        Text((try? source.resolve(source.root).path) ?? "Source unavailable — reconnect its drive or share.")
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
        .sheet(isPresented: $deckPresented) { SteamDeckLibraryView() }
    }
}
