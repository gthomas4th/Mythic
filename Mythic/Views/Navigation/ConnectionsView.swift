import SwiftUI
import Network

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
    @AppStorage("playStationClient") private var playStationClient = "sony"
    @State private var remotePlayApp: URL?
    @State private var playStationStatus = ""
    private let remotePlayGuide = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/lang/en/1100002.html")!
    private func findRemotePlay() {
        if playStationClient == "sony" {
            remotePlayApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.playstation.RemotePlay")
        } else {
            let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            remotePlayApp = roots.flatMap { root in ["chiaki-ng.app", "Chiaki-ng.app", "Chiaki.app"].map { root.appendingPathComponent($0) } }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
    private func openRemotePlay() {
        findRemotePlay()
        guard let app = remotePlayApp else {
            playStationStatus = "Install the selected client using its setup guide, then check again."
            return
        }
        Task {
            do {
                try await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                playStationStatus = "Remote Play client opened. Select your PS5 there to connect."
            } catch {
                playStationStatus = "Remote Play client could not open: " + error.localizedDescription
            }
        }
    }
    var body: some View {
        Form {
            Section("Home PC") {
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
            Section("PlayStation 5 · Remote Play") {
                Picker("Remote Play client", selection: $playStationClient) {
                    Text("Sony PS Remote Play").tag("sony")
                    Text("chiaki-ng").tag("chiaki")
                }.onChange(of: playStationClient) { _, _ in findRemotePlay(); playStationStatus = "" }
                Text("Stream your PS5 using the selected client. Pairing and streaming settings stay in that app.")
                Label(remotePlayApp == nil ? "Selected client not installed" : "Selected client installed",
                      systemImage: remotePlayApp == nil ? "arrow.down.app" : "checkmark.circle")
                HStack {
                    Button("Open Remote Play") { openRemotePlay() }.disabled(remotePlayApp == nil)
                    Button("Check installation") { findRemotePlay() }
                    if playStationClient == "sony" {
                        Link("Sony setup guide", destination: remotePlayGuide)
                    } else {
                        Link("chiaki-ng setup", destination: URL(string: "https://streetpea.github.io/chiaki-ng/setup/installation/")!)
                    }
                }
                Text(playStationClient == "sony" ? "Sign in with the same PlayStation account as your PS5, then select PS5." : "Register your PS5 in chiaki-ng using its setup guide, then test the stream before adjusting quality.")
                    .font(.callout).foregroundStyle(.secondary)
                Text(playStationClient == "sony" ? "Sony supports DualSense and DUALSHOCK 4 controllers. Your Apex 5 has not been tested with this app." : "chiaki-ng offers controller mapping and stream tuning. Stability and Apex 5 controls still need a live check.")
                    .font(.callout).foregroundStyle(.secondary)
                if !playStationStatus.isEmpty { Text(playStationStatus).font(.callout) }
            }
            if !message.isEmpty { Text(message) }
        }
        .formStyle(.grouped).navigationTitle("PC & PlayStation")
        .onAppear { findRemotePlay() }
    }
    private func open(stream: Bool) {
        Task {
            do { try await model.openMoonlight(stream: stream); message = "" } catch { message = "Could not open the stream. Check the address, Moonlight installation and pairing." }
        }
    }
}
