//
//  Engine.swift
//  Mythic
//
//  Created by vapidinfinity (esi) on 24/10/2025.
//

// Copyright © 2023-2025 vapidinfinity

import Foundation
import OSLog
import SemanticVersion
import AppKit

final class Engine {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "Engine"
    )
    
    // long ahh code
    static var releaseChannel: ReleaseChannel {
        get {
            UserDefaults.standard.register(defaults: ["engineChannel": ReleaseChannel.stable.rawValue])
            if let channelString = UserDefaults.standard.string(forKey: "engineChannel"),
               let channel: ReleaseChannel = .init(rawValue: channelString) {
                return channel
            }
            
            return .stable
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "engineChannel")
        }
    }
    
    static let directory = Bundle.appHome!.appending(path: "Engine")
    static let wineExecutableURL = directory.appending(path: "wine/bin/wine64")
    
    static var isInstalled: Bool {
        return FileManager.default.fileExists(atPath: directory.appending(path: "Properties.plist").path)
    }
    
    static var installedVersion: SemanticVersion? {
        get async {
            let properties = try? await retrieveEngineProperties()
            return properties?.version
        }
    }
    
    static func retrieveUpdateCatalog() async throws -> UpdateCatalog {
        let catalogURL = URL(string: "https://dl.getmythic.app/engine/EngineUpdateStream.plist")!
        let (data, response) = try await URLSession.shared.data(from: catalogURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        
        let decoder: PropertyListDecoder = .init()
        decoder.semanticVersionDecodingStrategy = .semverString
        
        let catalog = try decoder.decode(UpdateCatalog.self, from: data)
        
        if catalog.version != UpdateCatalog.nativeVersion {
            log.warning("""
            UpdateCatalog was parsed, but its version does not match that of the currently implemented version.
            An app update may be necessary.
            """)
        }
        
        return catalog
    }
    
    static func retrieveEngineProperties() async throws -> EngineProperties {
        guard isInstalled else { throw NotInstalledError() }
        
        let decoder: PropertyListDecoder = .init()
        decoder.semanticVersionDecodingStrategy = .defaultCodable
        
        let properties = directory.appending(path: "Properties.plist")
        return try decoder.decode(EngineProperties.self, from: .init(contentsOf: properties))
    }
    
    static func getLatestCompatibleRelease(for channelName: ReleaseChannel = releaseChannel) async throws -> UpdateCatalog.Release {
        let catalog = try await retrieveUpdateCatalog()
        
        guard let channel = catalog.channels[channelName],
              let latestCompatibleRelease = channel.latestCompatibleRelease else {
            throw UnableToRetrieveCompatibleReleaseError()
        }
        
        return latestCompatibleRelease
    }
    
    static func checkIfUpdateAvailable(for channelName: ReleaseChannel = releaseChannel) async throws -> Bool {
        let latestRelease: UpdateCatalog.Release = try await getLatestCompatibleRelease(for: channelName)
        let properties = try await retrieveEngineProperties()
        
        return latestRelease.version > properties.version
    }
    
    static func install() -> AsyncThrowingStream<InstallProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task(priority: .utility) {
                do {
                    guard !isInstalled else { continuation.finish(); return }
                    guard !FileManager.default.fileExists(atPath: directory.path) else {
                        throw EngineArtifactVerifier.VerificationError.existingDirectory
                    }
                    let release = try await getLatestCompatibleRelease()
                    let artifactURL = try EngineArtifactVerifier.secureURL(release.downloadURL)
                    guard let checksumLocation = release.checksumURL else {
                        throw EngineArtifactVerifier.VerificationError.missingChecksum
                    }
                    let checksumURL = try EngineArtifactVerifier.secureURL(checksumLocation)
                    let delegate = EngineDownloadDelegate { completed, total in
                        let progress = Progress(totalUnitCount: max(total, 1))
                        progress.completedUnitCount = total > 0 ? completed : 0
                        continuation.yield(.init(stage: .downloading, progress: progress))
                    }
                    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                    defer { session.invalidateAndCancel() }
                    let (bytes, checksumResponse) = try await session.bytes(from: checksumURL)
                    try validateArtifactResponse(checksumResponse)
                    var checksumData = Data()
                    for try await byte in bytes {
                        checksumData.append(byte)
                        guard checksumData.count <= 4096 else {
                            throw EngineArtifactVerifier.VerificationError.invalidChecksum
                        }
                    }
                    let expectedHash = try EngineArtifactVerifier.checksum(checksumData)
                    continuation.yield(.init(stage: .downloading, progress: Progress(totalUnitCount: 1)))
                    let (file, response) = try await session.download(from: artifactURL)
                    defer { try? FileManager.default.removeItem(at: file) }
                    try validateArtifactResponse(response)
                    try Task.checkCancellation()
                    try EngineArtifactVerifier.verify(file: file, expectedSHA256: expectedHash)
                    try Task.checkCancellation()

                    // Extract into our own staging folder. An existing runtime is never removed.
                    let staging = directory.deletingLastPathComponent()
                        .appendingPathComponent("Engine.installing-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: staging) }
                    continuation.yield(.init(stage: .installing, progress: Progress(totalUnitCount: 100)))
                    let process = Process()
                    process.executableURL = URL(filePath: "/usr/bin/tar")
                    process.arguments = ["-xJf", file.path, "-C", staging.path]
                    _ = try await process.runWrapped()
                    try Task.checkCancellation()
                    guard process.terminationStatus == 0,
                          FileManager.default.isExecutableFile(atPath: staging.appendingPathComponent("wine/bin/wine64").path) else {
                        throw EngineArtifactVerifier.VerificationError.incompleteEngine
                    }
                    let decoder = PropertyListDecoder()
                    decoder.semanticVersionDecodingStrategy = .defaultCodable
                    let properties = try decoder.decode(EngineProperties.self,
                        from: Data(contentsOf: staging.appendingPathComponent("Properties.plist")))
                    // Catalog versions omit build metadata (2.6.1); the archive may include it (2.6.1+0).
                    guard properties.version.major == release.version.major,
                          properties.version.minor == release.version.minor,
                          properties.version.patch == release.version.patch,
                          properties.version.preRelease == release.version.preRelease,
                          release.version.build.isEmpty || properties.version.build == release.version.build else {
                        throw EngineArtifactVerifier.VerificationError.incompleteEngine
                    }
                    let receipt = ["schemaVersion": "1", "engineVersion": receiptVersion(properties.version),
                                   "catalogVersion": receiptVersion(release.version),
                                   "sha256": expectedHash, "upstreamCommit": release.commitSHA]
                    let receiptData = try JSONEncoder().encode(receipt)
                    try receiptData.write(to: staging.appendingPathComponent("GameHubInstallReceipt.json"), options: .atomic)
                    try Task.checkCancellation()
                    // moveItem refuses an existing destination, including one created during download.
                    try FileManager.default.moveItem(at: staging, to: directory)
                    let completed = Progress(totalUnitCount: 100)
                    completed.completedUnitCount = 100
                    continuation.yield(.init(stage: .installing, progress: completed))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func receiptVersion(_ version: SemanticVersion) -> String {
        EngineArtifactVerifier.versionString(major: version.major, minor: version.minor, patch: version.patch,
                                             preRelease: version.preRelease, build: version.build)
    }

    private static func validateArtifactResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode), let url = response.url,
              url.scheme == "https", (try? EngineArtifactVerifier.secureURL(url.absoluteString)) == url else {
            throw EngineArtifactVerifier.VerificationError.invalidSource
        }
    }

    static func remove() async throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

extension Engine {
    @MainActor
    static func displayUpdateChecker(userInitiated: Bool) async {
        guard let window = NSApp.windows.first else { return }
        
        let isUpdateAvailable: Bool
        do {
            isUpdateAvailable = try await checkIfUpdateAvailable()
        } catch {
            if userInitiated {
                let alert: NSAlert = .init()
                alert.alertStyle = .critical
                alert.messageText = String(localized: "Unable to check for Mythic Engine updates.")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: String(localized: "OK"))
                
                await alert.beginSheetModal(for: window)
            }
            
            return
        }
        
        guard isUpdateAvailable else {
            if userInitiated {
                let alert: NSAlert = .init()
                alert.alertStyle = .informational
                alert.messageText = String(localized: "No Mythic Engine updates available.")
                alert.informativeText = String(localized: "You're currently on the latest version, \(await installedVersion?.description ?? String(localized: "an unknown version")).")
                alert.addButton(withTitle: String(localized: "OK"))
                
                await alert.beginSheetModal(for: window)
            }
            return
        }
        
        let latestVersion = (try? await getLatestCompatibleRelease())?.version.description ?? String(localized: "Unknown")
        let currentVersion = await installedVersion?.description ?? String(localized: "an unknown version", comment: "Of Mythic Engine")
        
        let updateAlert: NSAlert = .init()
        updateAlert.messageText = String(localized: "Mythic Engine update available.")
        updateAlert.informativeText = String(localized: """
            A new version of Mythic Engine (\(latestVersion)) has released.
            You're currently using \(currentVersion).
            """)
        updateAlert.addButton(withTitle: String(localized: "Update"))
        updateAlert.addButton(withTitle: String(localized: "Cancel"))
        
        let updateResponse = await updateAlert.beginSheetModal(for: window)
        guard case .alertFirstButtonReturn = updateResponse else { return }
        
        let confirmationAlert: NSAlert = .init()
        confirmationAlert.messageText = String(localized: "Are you sure you want to update now?")
        confirmationAlert.informativeText = String(localized: "This will remove the current version of Mythic Engine.") + String(localized: "The latest version will be installed the next time you attempt to launch a Windows® game.")
        confirmationAlert.addButton(withTitle: String(localized: "Update"))
        confirmationAlert.addButton(withTitle: String(localized: "Cancel"))
        
        let confirmationResponse = await confirmationAlert.beginSheetModal(for: window)
        guard case .alertFirstButtonReturn = confirmationResponse else { return }
        
        do {
            try await remove()
            
            let successAlert: NSAlert = .init()
            successAlert.alertStyle = .informational
            successAlert.messageText = String(localized: "Successfully removed Mythic Engine.")
            successAlert.informativeText = String(localized: "The latest version will be installed the next time you attempt to launch a Windows® game.")
            successAlert.addButton(withTitle: String(localized: "OK"))
            
            await successAlert.beginSheetModal(for: window)
        } catch {
            let errorAlert: NSAlert = .init()
            errorAlert.alertStyle = .critical
            errorAlert.messageText = String(localized: "Unable to remove Mythic Engine.")
            errorAlert.informativeText = error.localizedDescription
            errorAlert.addButton(withTitle: String(localized: "OK"))
            
            await errorAlert.beginSheetModal(for: window)
        }
    }
}

/// Restrict redirects as well as initial requests to the official HTTPS engine source.
private final class EngineDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: @Sendable (Int64, Int64) -> Void
    init(progress: @escaping @Sendable (Int64, Int64) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https",
              (try? EngineArtifactVerifier.secureURL(url.absoluteString)) == url else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
