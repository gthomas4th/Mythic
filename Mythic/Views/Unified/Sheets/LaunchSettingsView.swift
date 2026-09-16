import SwiftUI
import UniformTypeIdentifiers

struct LaunchSettingsView: View {
    var initialProfileID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var status = ""
    @State private var profiles: [CompatibilityProfile] = []
    @State private var selected = ""
    @State private var steamClosed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HubSectionBanner(title: "Launch Settings")
            Text("Working profiles stay pinned. App updates do not replace their runtime or touch saves.").foregroundStyle(.secondary)
            Picker("Compatibility profile", selection: $selected) {
                Text("Select a profile").tag("")
                ForEach(profiles, id: \.profileID) { Text($0.profileID).tag($0.profileID) }
            }
            if let profile = profiles.first(where: { $0.profileID == selected }) {
                LabeledContent("Runtime", value: profile.runtimeVersion)
                LabeledContent("Graphics", value: profile.rendererVersion)
                LabeledContent("Status", value: profile.validation == "owner-accepted" ? "Accepted by you" : "Testing")
                Text(profile.notes).font(.callout)
                Toggle("I have closed Windows Steam before switching profiles", isOn: $steamClosed)
                Button("Use this profile for the next launch") {
                    perform {
                        try GameHubRuntime.activate(profile)
                        status = "Selected for the next launch. Choose your accepted profile again to restore it."
                        steamClosed = false
                        Task { try? await GameDataStore.shared.refreshFromStorefronts(.steam) }
                    }
                }.disabled(!steamClosed)
                HStack {
                    Button("Export") { exportProfile(profile) }
                    Button("Clone for testing") {
                        perform {
                            _ = try GameHubRuntime.profiles.clone(profile.profileID, as: profile.profileID + "-" + String(UUID().uuidString.prefix(8)))
                            status = "Test copy created. Your accepted profile is unchanged."
                        }
                    }
                    Button("Roll back profile") {
                        perform { try GameHubRuntime.profiles.rollback(profile.profileID); status = "Previous settings restored. Saves were not changed." }
                    }
                }
            }
            HStack {
                Button("Import profile…") { importProfile() }
                Button("Export diagnostics…") {
                    let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "game-hub-diagnostics.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        perform { try LaunchDiagnostics.export().write(to: url, options: .atomic); status = "Exported sanitized launch diagnostics." }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(24).frame(width: 620)
        .font(.system(size: 16))
        .foregroundStyle(HubTheme.ink)
        .background(HubTheme.canvas)
        .task { selected = initialProfileID ?? ""; refresh() }
    }
    private func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(at: GameHubRuntime.profiles.directory, includingPropertiesForKeys: nil)) ?? []
        profiles = files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".previous.") }
            .compactMap { try? GameHubRuntime.profiles.load($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.profileID < $1.profileID }
        if selected.isEmpty { selected = profiles.first?.profileID ?? "" }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); refresh() } catch { status = "Could not change the profile: " + error.localizedDescription }
    }
    private func exportProfile(_ profile: CompatibilityProfile) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = profile.profileID + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            try profile.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profile).write(to: url, options: .atomic)
            status = "Exported settings. Local runtime paths and folder permissions are not included."
        }
    }
    private func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            var profile = try GameHubRuntime.profiles.decode(handle.read(upToCount: 65537) ?? Data())
            profile.profileID = "import-" + UUID().uuidString
            profile.validation = "testing"
            try GameHubRuntime.profiles.save(profile)
            selected = profile.profileID
            status = "Imported as a test copy. Accepted settings are unchanged."
        }
    }
}
