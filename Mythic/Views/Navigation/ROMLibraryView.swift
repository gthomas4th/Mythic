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
    /// Known mounted paths keep NAS sources usable after a share remount invalidates a bookmark.
    var fallbackRoot: String?
    var fallbackApplication: String?
    var fallbackCore: String?
    var index = ROMIndex()
    func resolve(_ data: Data, fallback: String? = nil) throws -> URL {
        // A configured source path identifies the actual current mounted folder. Prefer it to a
        // reusable bookmark copied from another source, which can resolve to a different folder.
        if let fallback, FileManager.default.fileExists(atPath: fallback) { return URL(fileURLWithPath: fallback) }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale), !stale { return url }
        throw GameHubRuntime.RuntimeError.access
    }
    func rootURL() throws -> URL { try resolve(root, fallback: fallbackRoot) }
    func applicationURL() throws -> URL {
        if let url = try? resolve(application, fallback: fallbackApplication) { return url }
        let name: String
        switch emulator {
        case .retroArch: name = "RetroArch"
        case .duckStation: name = "DuckStation"
        case .pcsx2: name = "PCSX2"
        case .rpcs3: name = "RPCS3"
        case .dolphin: name = "Dolphin"
        case .ryujinx: name = "Ryujinx"
        }
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/Applications")]
        for root in roots {
            let candidate = root.appendingPathComponent(name + ".app")
            if (try? EmulatorApplicationInfo.inspect(application: candidate)) != nil { return candidate }
        }
        throw ROMError.emulatorMissing
    }
    func coreURL() throws -> URL? {
        guard let core else { return nil }
        if let url = try? resolve(core, fallback: fallbackCore), FileManager.default.fileExists(atPath: url.path) { return url }
        guard emulator == .retroArch else { throw ROMError.coreMissing }
        let coreName: String
        switch system.lowercased() {
        case "n64", "nintendo 64": coreName = "mupen64plus_next_libretro.dylib"
        case "dreamcast": coreName = "flycast_libretro.dylib"
        case "megadrive", "mega drive", "genesis", "sega": coreName = "picodrive_libretro.dylib"
        default: throw ROMError.coreMissing
        }
        let candidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RetroArch/cores")
            .appendingPathComponent(coreName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { throw ROMError.coreMissing }
        return candidate
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
                    guard let root = try? source.rootURL() else { return (nil, nil) }
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
            let root = try source.rootURL()
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
                    status = "Scanning \(HubSystemMark.shortName(for: source.system))… Unchanged files reuse their saved hashes."
                    let root = try source.rootURL()
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
@MainActor final class EmulatorSessionCoordinator {
    static let shared = EmulatorSessionCoordinator()

    private var application: NSRunningApplication?
    private var terminationObserver: NSObjectProtocol?
    private var escapeMonitor: Any?
    private var shuttingDown = false

    var hasActiveSession: Bool { application?.isTerminated == false }

    func quitActiveSession() async {
        guard hasActiveSession else { return }
        await closeActiveSession(reactivateGameHub: true)
    }

    /// Prepares only the settings that an emulator cannot receive on its command line.
    /// Every other emulator keeps its native pause/quit behavior.
    func sessionConfiguration(for kind: EmulatorKind) throws -> URL? {
        switch kind {
        case .retroArch:
            let directory = GameHubRuntime.support.appendingPathComponent("Emulator Sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("retroarch-gamehub.cfg")
            let settings = """
            video_fullscreen = "true"
            video_windowed_fullscreen = "true"
            input_exit_emulator = "escape"
            quit_press_twice = "false"
            quit_on_close_content = "1"
            menu_pause_libretro = "true"
            config_save_on_exit = "false"
            """
            try settings.write(to: file, atomically: true, encoding: .utf8)
            return file
        case .ryujinx:
            try prepareRyujinxSettings()
            return nil
        case .dolphin:
            try prepareDolphinSettings()
            return nil
        default:
            return nil
        }
    }

    func launch(application url: URL, configuration: NSWorkspace.OpenConfiguration, kind: EmulatorKind) async throws {
        await closeActiveSession(reactivateGameHub: false)
        configuration.createsNewApplicationInstance = true
        let launched = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        application = launched
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  terminated.processIdentifier == launched.processIdentifier else { return }
            Task { @MainActor in self?.finish(launched, reactivateGameHub: true) }
        }
        if kind == .ryujinx {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in
                    await self?.closeActiveSession(reactivateGameHub: true)
                }
            }
        }
        launched.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    func applicationWillTerminate() {
        shuttingDown = true
        removeObserver()
        guard let application, !application.isTerminated else { return }
        if !application.terminate() { application.forceTerminate() }
        self.application = nil
    }

    private func closeActiveSession(reactivateGameHub: Bool) async {
        guard let application, !application.isTerminated else {
            finish(application, reactivateGameHub: reactivateGameHub)
            return
        }
        _ = application.terminate()
        for _ in 0..<20 where !application.isTerminated {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !application.isTerminated {
            _ = application.forceTerminate()
            for _ in 0..<10 where !application.isTerminated {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        finish(application, reactivateGameHub: reactivateGameHub)
    }

    private func finish(_ finishedApplication: NSRunningApplication?, reactivateGameHub: Bool) {
        guard finishedApplication == nil || application?.processIdentifier == finishedApplication?.processIdentifier else { return }
        removeObserver()
        application = nil
        guard reactivateGameHub, !shuttingDown else { return }
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.windows.first(where: { $0.canBecomeKey && $0.isVisible })?.makeKeyAndOrderFront(nil)
    }

    private func removeObserver() {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func prepareDolphinSettings() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dolphin/Config", isDirectory: true)
        let file = directory.appendingPathComponent("Dolphin.ini")
        guard let original = try? String(contentsOf: file, encoding: .utf8) else { return }
        var updated = setting("Fullscreen", to: "True", in: "Display", text: original)
        updated = setting("ConfirmStop", to: "False", in: "Interface", text: updated)
        if updated != original {
            let backup = directory.appendingPathComponent("Dolphin.before-gamehub-session.ini")
            if !FileManager.default.fileExists(atPath: backup.path) {
                try original.write(to: backup, atomically: true, encoding: .utf8)
            }
            try updated.write(to: file, atomically: true, encoding: .utf8)
        }

        let hotkeys = directory.appendingPathComponent("Hotkeys.ini")
        let originalHotkeys = (try? String(contentsOf: hotkeys, encoding: .utf8)) ?? ""
        var updatedHotkeys = setting("Device", to: "Quartz/0/Keyboard & Mouse", in: "Hotkeys", text: originalHotkeys)
        updatedHotkeys = setting("General/Stop", to: "Escape", in: "Hotkeys", text: updatedHotkeys)
        if updatedHotkeys != originalHotkeys {
            let hotkeyBackup = directory.appendingPathComponent("Hotkeys.before-gamehub-session.ini")
            if !originalHotkeys.isEmpty, !FileManager.default.fileExists(atPath: hotkeyBackup.path) {
                try originalHotkeys.write(to: hotkeyBackup, atomically: true, encoding: .utf8)
            }
            try updatedHotkeys.write(to: hotkeys, atomically: true, encoding: .utf8)
        }
    }

    private func setting(_ key: String, to value: String, in section: String, text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        let header = "[\(section)]"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines += [header, "\(key) = \(value)"]
            return lines.joined(separator: "\n")
        }
        let end = lines[(start + 1)...].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? lines.endIndex
        if let index = lines[(start + 1)..<end].firstIndex(where: {
            $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == key
        }) {
            lines[index] = "\(key) = \(value)"
        } else {
            lines.insert("\(key) = \(value)", at: end)
        }
        return lines.joined(separator: "\n")
    }

    private func prepareRyujinxSettings() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ryujinx", isDirectory: true)
        let file = directory.appendingPathComponent("Config.json")
        guard let data = try? Data(contentsOf: file),
              var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let desired: [String: Bool] = [
            "start_fullscreen": true,
            "start_no_ui": true,
            "show_console": false,
            "show_confirm_exit": false
        ]
        guard desired.contains(where: { settings[$0.key] as? Bool != $0.value }) else { return }
        let backup = directory.appendingPathComponent("Config.before-gamehub-session.json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try data.write(to: backup, options: .atomic)
        }
        for (key, value) in desired { settings[key] = value }
        let updated = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try updated.write(to: file, options: .atomic)
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
        super.init(id: entry.id, title: ROMTitle.displayName(entry.title), installationState: .installed(location: content, platform: .macOS))
    }
    required init(from decoder: any Decoder) throws { source = nil; entry = nil; try super.init(from: decoder) }
    @MainActor override func _launch() async throws {
        guard let source, let entry else { throw ROMError.invalid }
        let root: URL
        if let copy = ROMLibrary.shared.localCopies[id], copy.selected {
            var stale = false
            root = try URL(resolvingBookmarkData: copy.root, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale)
            guard !stale else { throw ROMError.missingPart }
        } else {
            do { root = try source.rootURL() }
            catch {
                throw NSError(domain: "GameHub.ROMSource", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Cannot access the ROM folder. Reconnect its server share or drive, then press Play again. (\(error.localizedDescription))"])
            }
        }
        let app = try source.applicationURL()
        let core = try source.coreURL()
        let urls = [root, app] + [core].compactMap { $0 }
        let access = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (index, url) in urls.enumerated() where access[index] { url.stopAccessingSecurityScopedResource() } }
        let content = root.appendingPathComponent(entry.relativePath).resolvingSymlinksInPath()
        _ = try ROMIndex.parts(of: content, root: root)
        _ = try EmulatorApplicationInfo.inspect(application: app)
        guard core.map({ FileManager.default.fileExists(atPath: $0.path) }) ?? true else { throw ROMError.coreMissing }
        let config = NSWorkspace.OpenConfiguration()
        let sessionConfiguration = try EmulatorSessionCoordinator.shared.sessionConfiguration(for: source.emulator)
        config.arguments = try EmulatorCommand.arguments(kind: source.emulator, content: content, core: core,
            dolphinPreset: source.dolphinPreset ?? .emulatorSettings, sessionConfiguration: sessionConfiguration)
        try await EmulatorSessionCoordinator.shared.launch(application: app, configuration: config, kind: source.emulator)
    }
}

enum ROMCatalogPolicy {
    private static let specialFolders: Set<String> = [
        "hack", "hacks", "homebrew", "homebrew & unlicensed", "unlicensed",
        "translation", "translations", "unreleased"
    ]

    /// The final artwork audit removed unresolved entries from the active ROM
    /// sources, so no valid catalog item needs to be hidden here.
    private static let hiddenWithoutArtwork: Set<String> = []

    static func isHacksOrHomebrew(_ game: Game) -> Bool {
        guard let entry = (game as? ROMGame)?.entry else { return false }
        let components = entry.relativePath.split(separator: "/").dropLast().map { $0.lowercased() }
        return components.contains { specialFolders.contains($0) }
    }

    static func isHiddenWithoutArtwork(_ game: Game) -> Bool {
        game is ROMGame && hiddenWithoutArtwork.contains(game.id)
    }

    static func deduplicationKey(for game: ROMGame) -> String {
        let system = game.source?.system.lowercased() ?? "rom"
        return system + "|" + game.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func prefers(_ candidate: ROMGame, over current: ROMGame) -> Bool {
        let candidateExtension = URL(fileURLWithPath: candidate.entry?.relativePath ?? "").pathExtension.lowercased()
        let currentExtension = URL(fileURLWithPath: current.entry?.relativePath ?? "").pathExtension.lowercased()
        // Extracted disc/cart images are launchable by every configured emulator;
        // archives are retained as a fallback but should not create another tile.
        if (candidateExtension != "zip") != (currentExtension != "zip") {
            return candidateExtension != "zip"
        }
        let candidateRaw = candidate.entry?.title ?? candidate.title
        let currentRaw = current.entry?.title ?? current.title
        let candidateRevision = revisionScore(candidateRaw)
        let currentRevision = revisionScore(currentRaw)
        if candidateRevision != currentRevision { return candidateRevision > currentRevision }
        if candidateRaw.count != currentRaw.count { return candidateRaw.count < currentRaw.count }
        return (candidate.entry?.relativePath ?? "").localizedStandardCompare(current.entry?.relativePath ?? "") == .orderedAscending
    }

    private static func revisionScore(_ value: String) -> Int {
        let patterns = [#"(?i)\bv(\d+)(?:\.(\d+))?"#, #"(?i)\brev(?:ision)?[-\s]*(\d+|[A-Z])"#]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let majorRange = Range(match.range(at: 1), in: value) else { continue }
            let majorText = String(value[majorRange])
            let major = Int(majorText) ?? Int(majorText.uppercased().unicodeScalars.first?.value ?? 64) - 64
            var minor = 0
            if match.numberOfRanges > 2, let minorRange = Range(match.range(at: 2), in: value) {
                minor = Int(value[minorRange]) ?? 0
            }
            return max(0, major) * 1_000 + minor
        }
        return 0
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
                        LabeledContent(HubSystemMark.shortName(for: source.system), value: "\(source.index.entries.count) games · \(source.emulator.displayName)")
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

struct HacksHomebrewView: View {
    @Bindable private var gameDataStore = GameDataStore.shared
    @State private var input = HubControllerInput.shared
    @State private var search = ""
    @State private var selectedSystem = ""
    @State private var selection = 0
    @State private var gridColumns = 1
    @State private var launchMessage = ""
    @AppStorage("gameCardSize") private var gameCardSize: Double = 200
    @AppStorage("hubTheme") private var theme = "lcars"

    private var allGames: [Game] {
        gameDataStore.hacksAndHomebrewLibrary.sorted {
            ROMTitle.sortKeyForDisplayName($0.title).localizedStandardCompare(ROMTitle.sortKeyForDisplayName($1.title)) == .orderedAscending
        }
    }
    private var systems: [String] {
        Set(allGames.map(GameListViewModel.systemName(for:))).sorted()
    }
    private var games: [Game] {
        allGames.filter {
            (search.isEmpty || $0.title.localizedStandardContains(search)) &&
            (selectedSystem.isEmpty || GameListViewModel.systemName(for: $0) == selectedSystem)
        }
    }
    private func updateColumns(_ width: CGFloat) {
        gridColumns = max(1, Int((Double(width) - 34) / (max(240, gameCardSize) + 22)))
    }
    private func controllerAction(_ action: String) -> Bool {
        if action == "back" || action == "sidebar" { return false }
        if action == "filter" {
            let choices = [""] + systems
            let current = choices.firstIndex(of: selectedSystem) ?? 0
            selectedSystem = choices[(current + 1) % choices.count]
            selection = 0
            return true
        }
        guard !games.isEmpty else { return false }
        selection = min(selection, games.count - 1)
        switch action {
        case "left", "right", "up", "down":
            selection = HubGridNavigation.destination(from: selection, action: action, columns: gridColumns, count: games.count)
        case "options": HubGameOptions.shared.open(games[selection])
        case "select":
            let game = games[selection]
            Task { do { try await game.launch(); launchMessage = "" } catch { launchMessage = error.localizedDescription } }
        default: return false
        }
        return true
    }

    var body: some View {
        let selectedID = games.indices.contains(selection) ? games[selection].id : nil
        VStack(spacing: 0) {
            HubSectionBanner(title: "Hacks & Homebrew")
                .padding(.horizontal, 28).padding(.vertical, 16)
            if input.connected {
                HubControllerHints(actions: [("Move", "Move"), ("A", "Play"), ("X", "Options"), ("Y", "System"), ("B", "Sidebar")])
                    .padding(.bottom, 12)
            }
            if !launchMessage.isEmpty { Text(launchMessage).padding(8) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryButton("All", system: nil)
                    ForEach(systems, id: \.self) { system in categoryButton(system, system: system) }
                }.padding(.horizontal, 28)
            }.padding(.bottom, 12)
            if games.isEmpty {
                ContentUnavailableView("No matching titles", systemImage: "hammer",
                    description: Text("Try another system or clear the search."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [.init(.adaptive(minimum: max(240, gameCardSize)), spacing: 22)], spacing: 24) {
                            ForEach(games) { game in
                                GameCard(game: .constant(game))
                                    .padding(4)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                                        input.connected && input.contentFocused && selectedID == game.id ? HubTheme.yellow : .clear,
                                        lineWidth: 3))
                                    .id(game.id)
                            }
                        }.padding(28)
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.onAppear { updateColumns(geometry.size.width) }
                            .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
                    })
                    .onChange(of: selection) { _, _ in if let selectedID { proxy.scrollTo(selectedID, anchor: .center) } }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search hacks and homebrew")
        .onAppear { input.setContent("hacks-homebrew", action: controllerAction) }
        .onDisappear { input.clearContent("hacks-homebrew") }
        .onChange(of: games.map(\.id)) { _, ids in selection = min(selection, max(0, ids.count - 1)) }
        .background(theme == "lcars" ? HubTheme.canvas : Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Hacks & Homebrew")
    }

    private func categoryButton(_ title: String, system: String?) -> some View {
        Button {
            selectedSystem = system ?? ""; selection = 0
        } label: {
            HStack(spacing: 7) {
                if let system { HubSystemMark(system: system, size: 20) }
                else { Image(systemName: "hammer.fill") }
                Text(title)
            }
            .font(.system(size: 15, weight: .bold)).lineLimit(1)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(HubTheme.ink)
            .background(selectedSystem == (system ?? "") ? HubTheme.yellow : HubTheme.blue.opacity(0.18), in: .capsule)
        }.buttonStyle(.plain)
    }
}
