// Copyright © 2026 Game Hub contributors
import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor final class SteamDeckLibraryStore: ObservableObject {
    static let shared = SteamDeckLibraryStore()
    @Published private(set) var inventory = SteamDeckInventory()
    @Published private(set) var isImporting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var importSummary: String?
    private var savedInventoryIsUnreadable = false
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameHub", isDirectory: true)
            .appendingPathComponent("steam-deck-shortcuts.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                defer { try? handle.close() }
                inventory = try SteamDeckInventory.decode(handle.read(upToCount: SteamShortcutImporter.maximumBytes + 1) ?? Data())
            } catch {
                savedInventoryIsUnreadable = true
                errorMessage = SteamShortcutImportError.invalidInventory.localizedDescription
            }
        }
    }

    var canImport: Bool { !isImporting && !savedInventoryIsUnreadable }

    func importFile(_ result: Result<[URL], Error>) {
        guard canImport else { return }
        let url: URL
        do {
            guard let selected = try result.get().first else { return }
            url = selected
        } catch {
            errorMessage = "No shortcut file was imported. Try choosing the file again."
            return
        }
        isImporting = true
        errorMessage = nil
        importSummary = nil
        let deviceID = inventory.deviceID
        Task {
            defer { isImporting = false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try await Task.detached(priority: .utility) {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true else { throw SteamShortcutImportError.malformed }
                    guard (values.fileSize ?? 0) <= SteamShortcutImporter.maximumBytes else { throw SteamShortcutImportError.tooLarge }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: SteamShortcutImporter.maximumBytes + 1) ?? Data()
                    return try SteamShortcutImporter.parse(data, deviceID: deviceID)
                }.value
                let merged = try inventory.merging(imported)
                let folder = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let encoded = try encoder.encode(merged)
                guard encoded.count <= SteamShortcutImporter.maximumBytes else { throw SteamShortcutImportError.tooLarge }
                try encoded.write(to: fileURL, options: .atomic)
                inventory = merged
                importSummary = imported.isEmpty ? "The file contains no shortcuts. Existing references were kept."
                    : "Imported \(imported.count) shortcuts. Your Steam Deck files and launch settings are unchanged."
            } catch let error as SteamShortcutImportError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "The inventory could not be imported or saved. Check file access and available disk space; your previous inventory was kept."
            }
        }
    }
}

struct SteamDeckLibraryView: View {
    @ObservedObject private var store = SteamDeckLibraryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isImporterPresented = false
    @State private var search = ""

    private var visibleShortcuts: [SteamDeckShortcut] {
        store.inventory.shortcuts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .padding(12)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your Steam Deck library").font(.title2.bold())
                    Text("Keep track of your games before their files arrive on this Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 24) {
                metric("Shortcuts", value: store.inventory.shortcuts.count)
                metric("ROM references", value: store.inventory.shortcuts.filter(\.isROMReference).count)
                Label("Local play not configured", systemImage: "externaldrive.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
            Divider()
            if store.inventory.shortcuts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Bring the list first. Copy the games later.").font(.headline)
                    Text("In Desktop Mode on your Deck, close Steam and copy shortcuts.vdf from your Steam userdata account’s config folder to this Mac. Then import that copy here.")
                    Text("This reads the list only. It does not move ROMs, change Deck shortcuts, or run imported commands.")
                        .foregroundStyle(.secondary)
                    Text("Steam purchases stay in the main Steam library. Non-Steam entries remain separate, even when names match.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
            } else {
                TextField("Search Deck shortcuts", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Deck shortcuts")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if visibleShortcuts.isEmpty {
                            Text("No matching shortcuts.").foregroundStyle(.secondary).padding()
                        }
                        ForEach(visibleShortcuts) { shortcut in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(shortcut.title).font(.headline)
                                    Spacer()
                                    Label(shortcut.isROMReference ? "Files on Steam Deck" : "Target not resolved",
                                          systemImage: shortcut.isROMReference ? "externaldrive" : "questionmark.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(shortcut.isROMReference ? "Steam Deck ROM shortcut · Not available on this Mac"
                                     : "Non-Steam shortcut · Not a Steam purchase")
                                    .font(.callout).foregroundStyle(.secondary)
                                if let path = shortcut.romPath {
                                    Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .textSelection(.enabled).lineLimit(2)
                                }
                            }
                            .padding(14)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                        }
                    }
                }
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
            }
            if let summary = store.importSummary { Text(summary).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Text("References are saved on this Mac and remain visible offline.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.isImporting { ProgressView().controlSize(.small) }
                Button("Import shortcuts.vdf…") { isImporterPresented = true }
                    .buttonStyle(.borderedProminent).disabled(!store.canImport)
            }
        }
        .padding(24)
        .frame(minWidth: 650, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.item], allowsMultipleSelection: false) {
            store.importFile($0)
        }
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
