// Development-only native host for isolated Wine runtime acceptance tests.
// Build artifacts, local paths, prefixes and logs belong in ignored .build-local.
import AppKit

@MainActor
final class RuntimeTestHost: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Ready to test the isolated runtime.")
    private var launched: Process?
    private var logHandle: FileHandle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Game Hub — Free Runtime Test"
        let title = NSTextField(labelWithString: "Windows Steam · Sikarugir Wine 10")
        title.font = .boldSystemFont(ofSize: 19)
        let detail = NSTextField(wrappingLabelWithString: "This test uses a copied Steam container. The original Game Hub engine is preserved.")
        let start = NSButton(title: "Launch Windows Steam", target: self, action: #selector(startSteam))
        let install = NSButton(title: "Install Rebirth", target: self, action: #selector(installRebirth))
        let stop = NSButton(title: "Stop Test Container", target: self, action: #selector(stopSteam))
        let buttons = NSStackView(views: [start, install, stop])
        let stack = NSStackView(views: [title, detail, buttons, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func path(_ key: String) throws -> URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, value.hasPrefix("/") else {
            throw NSError(domain: "RuntimeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing test configuration: \(key)"])
        }
        return URL(fileURLWithPath: value)
    }

    private func process(tool: String, arguments: [String]) throws -> Process {
        let runtime = try path("TestRuntimeRoot")
        let prefix = try path("TestPrefix")
        guard FileManager.default.fileExists(atPath: prefix.appendingPathComponent("drive_c").path) else {
            throw NSError(domain: "RuntimeTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Test container is missing."])
        }
        let process = Process()
        process.executableURL = runtime.appendingPathComponent("bin/\(tool)")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = "-all,err+all"
        environment["PATH"] = runtime.appendingPathComponent("bin").path + ":/usr/bin:/bin"
        process.environment = environment
        return process
    }

    @objc private func startSteam() {
        guard launched?.isRunning != true else { status.stringValue = "Steam is already running in the test container."; return }
        do {
            let prefix = try path("TestPrefix")
            let executable = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            let process = try process(tool: "wine", arguments: [executable.path])
            process.currentDirectoryURL = executable.deletingLastPathComponent()
            let log = try path("TestLog")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            logHandle = try FileHandle(forWritingTo: log)
            try logHandle?.seekToEnd()
            process.standardOutput = logHandle
            process.standardError = logHandle
            try process.run()
            launched = process
            status.stringValue = "Steam started. First launch may update the copied container."
        } catch { status.stringValue = error.localizedDescription }
    }

    @objc private func installRebirth() {
        do {
            let prefix = try path("TestPrefix")
            let executable = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            let request = try process(tool: "wine", arguments: [executable.path, "steam://install/2909400"])
            request.currentDirectoryURL = executable.deletingLastPathComponent()
            try request.run()
            status.stringValue = "Rebirth installation requested in Windows Steam."
        } catch { status.stringValue = error.localizedDescription }
    }

    @objc private func stopSteam() {
        do {
            let process = try process(tool: "wineserver", arguments: ["-k"])
            try process.run()
            status.stringValue = "Stop requested for the test container."
        } catch { status.stringValue = error.localizedDescription }
    }
}
@main
struct RuntimeTestMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = RuntimeTestHost()
        app.delegate = delegate
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Runtime Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)
        app.mainMenu = menu
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
