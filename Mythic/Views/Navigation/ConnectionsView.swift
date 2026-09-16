import SwiftUI
import Network
import Darwin

@Observable final class ConnectionGame: Game {
    enum Destination: String, Codable { case yoda, playStation5 }

    let destination: Destination
    var artworkAssetName: String { destination == .yoda ? "ConnectionYoda" : "ConnectionPS5" }
    override var storefront: Storefront? { .local }
    override var locationLabel: String? { destination == .yoda ? "PC" : "PS5" }
    override var typeLabel: String? { "Remote Play" }
    override var supportsFileManagement: Bool { false }
    override var supportsLaunchArguments: Bool { false }
    override var canPlayFromLocation: Bool { applicationURL != nil }

    private var applicationURL: URL? {
        let bundleID = destination == .yoda ? "com.moonlight-stream.Moonlight" : "org.streetpea.chiaking"
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return registered }
        let name = destination == .yoda ? "Moonlight.app" : "chiaki-ng.app"
        return [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            .map { $0.appendingPathComponent(name) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init(destination: Destination) {
        self.destination = destination
        let fallback = URL(fileURLWithPath: destination == .yoda ? "/Applications/Moonlight.app" : "/Applications/chiaki-ng.app")
        super.init(id: "connection:\(destination.rawValue)",
                   title: destination == .yoda ? "Yoda" : "PS5 Remote Play",
                   installationState: .installed(location: fallback, platform: .macOS))
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Game.CodingKeys.self)
        let decodedID = try values.decode(String.self, forKey: .id)
        destination = decodedID.contains("playStation5") ? .playStation5 : .yoda
        try super.init(from: decoder)
    }

    @MainActor override func _launch() async throws {
        switch destination {
        case .yoda:
            try await HubConnections.shared.openMoonlight(stream: true)
        case .playStation5:
            guard let applicationURL else { throw CocoaError(.fileNoSuchFile) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.arguments = ["--exit-app-on-stream-exit"]
            try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
        }
    }

    @MainActor override func _move(from currentLocation: URL, to newLocation: URL) async throws {
        throw CocoaError(.featureUnsupported)
    }
    override func _verifyInstallation() async throws { throw CocoaError(.featureUnsupported) }
    @MainActor override func _update() async throws { throw CocoaError(.featureUnsupported) }

    static func libraryGames() -> Set<Game> {
        [ConnectionGame(destination: .playStation5), ConnectionGame(destination: .yoda)]
    }
}

@MainActor @Observable final class HubConnections {
    static let shared = HubConnections()
    var host = RemoteHost(name: "Home PC", address: "", application: "Desktop") {
        didSet {
            guard host.address != oldValue.address else { return }
            reachable = false; checking = false
            connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
            timeout?.cancel(); timeout = nil
            attemptID = UUID()
            resolveWaiters(false)
            status = "Address changed. Test this PC before selecting its game targets."
            Task { try? await GameDataStore.shared.refreshFromStorefronts(.steam) }
        }
    }
    var status = "Add your Home PC address to test its streaming service."
    var checking = false
    var reachable = false
    var steamApplications: [String: String] = [:]
    private let mappingFile = GameHubRuntime.support.appendingPathComponent("remote-steam-mappings.json")
    private var connection: NWConnection?
    private var timeout: Task<Void, Never>?
    private var attemptID = UUID()
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private let file = GameHubRuntime.support.appendingPathComponent("remote-host.json")
    init() {
        if let data = try? Data(contentsOf: mappingFile), let saved = try? JSONDecoder().decode([String: String].self, from: data) { steamApplications = saved }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(RemoteHost.self, from: data), (try? saved.validate()) != nil { host = saved }
        Task { if !host.address.isEmpty { test() } }
    }
    func save() throws {
        try host.validate()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(host).write(to: file, options: .atomic)
    }
    func test() {
        guard !checking else { return }
        do { try save() } catch { reachable = false; finish(error.localizedDescription); return }
        reachable = false; checking = true; status = "Checking streaming port…"
        let start = Date()
        let checkedAddress = host.address
        let identifier = UUID(); attemptID = identifier
        let attempt = NWConnection(host: NWEndpoint.Host(host.address), port: 47989, using: .tcp)
        connection = attempt
        attempt.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.checking, self.attemptID == identifier, self.host.address == checkedAddress else { return }
                switch state {
                case .ready: self.reachable = true; self.finish(RemoteHealthClassifier.description(reachable: true, relayed: nil, milliseconds: Date().timeIntervalSince(start) * 1000))
                case .failed: self.finish(RemoteHealthClassifier.description(reachable: false, relayed: nil, milliseconds: nil))
                default: break
                }
            }
        }
        attempt.start(queue: .global(qos: .utility))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, self?.attemptID == identifier else { return }
            self?.finish("Streaming port unavailable. Check the PC address and Sunshine on the PC.")
        }
    }
    func checkReachability() async -> Bool {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            test()
        }
    }
    private func resolveWaiters(_ result: Bool) {
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume(returning: result) }
    }
    private func finish(_ message: String) {
        checking = false; status = message
        resolveWaiters(reachable)
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        timeout?.cancel(); timeout = nil
        Task { try? await GameDataStore.shared.refreshFromStorefronts(.steam) }
    }
    func saveMapping(appID: String, application: String) throws {
        guard SteamLaunch.url(appID: appID) != nil else { throw RemoteHost.RemoteError.invalid }
        var mappedHost = host; mappedHost.application = application; try mappedHost.validate()
        var updated = steamApplications; updated[appID] = application
        try FileManager.default.createDirectory(at: mappingFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: mappingFile, options: .atomic)
        steamApplications = updated
        Task { try? await GameDataStore.shared.refreshFromStorefronts(.steam) }
    }
    func targets(for records: [GameRecord]) -> [GameRecord] {
        records.map { record in
            guard let application = steamApplications[record.id.externalID], !host.address.isEmpty,
                  SteamLaunch.url(appID: record.id.externalID) != nil else { return record }
            var selectedHost = host; selectedHost.application = application
            guard (try? selectedHost.validate()) != nil else { return record }
            let app = URL(fileURLWithPath: "/Applications/Moonlight.app")
            let target = LaunchTarget(id: record.id.description + ":home-pc", kind: .moonlight,
                locator: URL(string: "https://moonlight-stream.org")!, application: app,
                available: reachable && FileManager.default.fileExists(atPath: app.path))
            return GameRecord(id: record.id, title: record.title,
                launchTargets: record.launchTargets.filter { $0.kind != .moonlight } + [target], artwork: record.artwork)
        }
    }
    func openMoonlight(stream: Bool, application: String? = nil) async throws {
        try save()
        let app = URL(fileURLWithPath: "/Applications/Moonlight.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw CocoaError(.fileNoSuchFile) }
        let config = NSWorkspace.OpenConfiguration()
        var selectedHost = host
        if let application { selectedHost.application = application }
        try selectedHost.validate()
        // Launch Services ignores arguments when reusing an existing application.
        // A stream request needs a fresh Moonlight invocation to select its game.
        config.createsNewApplicationInstance = stream
        config.arguments = stream ? selectedHost.arguments : []
        try await NSWorkspace.shared.openApplication(at: app, configuration: config)
    }
}

struct ConnectionsView: View {
    @Bindable private var model = HubConnections.shared
    @State private var message = ""
    @State private var steamID = ""
    @State private var remoteApplication = ""
    @State private var remotePlayApp: URL?
    @State private var playStationStatus = ""
    @State private var closingRemotePlay = false
    private func findRemotePlay() {
        remotePlayApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.streetpea.chiaking")
        if remotePlayApp == nil {
            let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            remotePlayApp = roots.map { $0.appendingPathComponent("chiaki-ng.app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
    private func openRemotePlay() {
        findRemotePlay()
        guard let app = remotePlayApp else {
            playStationStatus = "Install chiaki-ng using its setup guide, then check again."
            return
        }
        Task {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = ["--exit-app-on-stream-exit"]
                try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                playStationStatus = "chiaki-ng opened. Select your PS5 to connect."
            } catch {
                playStationStatus = "chiaki-ng could not open: " + error.localizedDescription
            }
        }
    }
    private func isChiakiProcess(_ application: NSRunningApplication) -> Bool {
        guard application.bundleIdentifier == "org.streetpea.chiaking",
              let executable = application.executableURL else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(application.processIdentifier, &path, UInt32(path.count)) > 0 else { return false }
        return URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath() == executable.resolvingSymlinksInPath()
    }
    private func closeRemotePlay() {
        guard !closingRemotePlay else { return }
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "org.streetpea.chiaking").filter(isChiakiProcess)
        guard !applications.isEmpty else { playStationStatus = "chiaki-ng is already closed."; return }
        closingRemotePlay = true
        playStationStatus = "Closing chiaki-ng…"
        Task { @MainActor in
            defer { closingRemotePlay = false }
            for application in applications { application.terminate() }
            for _ in 0..<25 {
                if !applications.contains(where: isChiakiProcess) { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            let stalled = applications.filter(isChiakiProcess)
            for application in stalled where isChiakiProcess(application) {
                kill(application.processIdentifier, SIGKILL)
            }
            for _ in 0..<10 {
                if !applications.contains(where: isChiakiProcess) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            playStationStatus = !applications.contains(where: isChiakiProcess)
                ? (stalled.isEmpty ? "chiaki-ng closed." : "chiaki-ng stopped responding and was force-closed.")
                : "chiaki-ng could not close. Use macOS Force Quit."
        }
    }
    var body: some View {
        Form {
            Section("Home PC") {
                HubTagBadge(title: "PC", category: "Location")
                TextField("Name", text: $model.host.name)
                TextField("Address", text: $model.host.address)
                TextField("Sunshine application", text: $model.host.application)
                Text("Start with Desktop. Pair this Mac in Moonlight once; approve its PIN on your PC.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Test connection") { model.test() }.disabled(model.checking)
                    Button("Open Moonlight") { open(stream: false) }
                    Button("Play on Home PC") { open(stream: true) }
                }
                Text(model.status).font(.callout)
                Text("1080p · 60 FPS target · 20 Mb/s. These are starting settings, not measured stream performance. No router or firewall changes are made.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Per-game Home PC target") {
                TextField("Steam app ID", text: $steamID)
                TextField("Exact Sunshine application name", text: $remoteApplication)
                Button("Add Home PC target") {
                    do { try model.saveMapping(appID: steamID, application: remoteApplication); message = "Home PC target saved. Test the connection, then select Play using in Library." } catch { message = "Enter a valid Steam app ID, host address and Sunshine application name." }
                }
                Text("Map an application that already exists in Sunshine. The hub does not change the PC configuration.").font(.caption).foregroundStyle(.secondary)
            }
            Section("PlayStation 5 · chiaki-ng") {
                HubTagBadge(title: "PS5", category: "Location")
                Text("Play your PS5 through chiaki-ng. Your paired console, account and streaming preferences are saved in the app.")
                Label(remotePlayApp == nil ? "chiaki-ng not installed" : "chiaki-ng installed",
                      systemImage: remotePlayApp == nil ? "arrow.down.app" : "checkmark.circle")
                HStack {
                    Button("Open chiaki-ng") { openRemotePlay() }.disabled(remotePlayApp == nil)
                    Button("Close chiaki-ng") { closeRemotePlay() }.disabled(closingRemotePlay)
                    Button("Check installation") { findRemotePlay() }
                    Link("Setup guide", destination: URL(string: "https://streetpea.github.io/chiaki-ng/setup/configuration/")!)
                }
                Text("Select your console in chiaki-ng. Closing a stream exits the app. Away from home, use its Remote Connection via PSN option.")
                    .font(.callout).foregroundStyle(.secondary)
                if !playStationStatus.isEmpty { Text(playStationStatus).font(.callout) }
            }
            if !message.isEmpty { Text(message) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .font(.system(size: 16))
        .foregroundStyle(HubTheme.ink)
        .background(HubTheme.canvas)
        .navigationTitle("PC & PlayStation")
        .onAppear { findRemotePlay() }
    }
    private func open(stream: Bool) {
        Task {
            do { try await model.openMoonlight(stream: stream); message = "" } catch { message = "Could not open the stream. Check the address, Moonlight installation and pairing." }
        }
    }
}
