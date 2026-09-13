// Copyright © 2023-2025 vapidinfinity; Game Hub contributors
import Foundation
import AppKit

/// Temporary bridge into the existing UI. Steam records never enter the legacy defaults blob.
final class SteamGame: Game {
    var record: GameRecord?
    var preferredTargetID: String?
    override var storefront: Storefront? { .steam }
    override var supportsFileManagement: Bool { false }
    override var supportsLaunchArguments: Bool { false }
    override func getSupportedPlatforms() -> Set<Game.Platform>? {
        Set((record?.launchTargets ?? []).map { $0.kind == .nativeMac ? .macOS : .windows })
    }

    init(record: GameRecord, target: LaunchTarget) {
        self.record = record
        super.init(id: record.id.description, title: record.title,
                   installationState: .installed(location: target.application, platform: target.kind == .nativeMac ? .macOS : .windows))
        _verticalImageURL = record.artwork
    }
    required init(from decoder: any Decoder) throws { try super.init(from: decoder) }

    @MainActor override func _launch() async throws {
        guard let record, let target = LaunchResolver.resolve(record.launchTargets, preferredID: preferredTargetID) else {
            throw GameHubRuntime.RuntimeError.unconfigured
        }
        if target.kind == .moonlight {
            guard let application = HubConnections.shared.steamApplications[record.id.externalID] else { throw GameHubRuntime.RuntimeError.unconfigured }
            try await HubConnections.shared.openMoonlight(stream: true, application: application)
            return
        }
        if target.kind == .wineSteam {
            guard let profileID = target.profileID else { throw GameHubRuntime.RuntimeError.unconfigured }
            try await GameHubRuntime.launch(appID: record.id.externalID, profileID: profileID)
            return
        }
        guard id.hasPrefix("steam:"),
              let url = SteamLaunch.url(appID: String(id.dropFirst(6))),
              case .installed = installationState,
              SteamNativeProvider.nativeApplication(in: target.application) != nil else {
            throw LaunchError.payloadUnavailable
        }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { throw LaunchError.clientMissing }
        guard NSWorkspace.shared.open(url) else { throw LaunchError.openFailed }
    }
    @MainActor override func _move(from currentLocation: URL, to newLocation: URL) async throws {
        throw LaunchError.managedBySteam
    }
    override func _verifyInstallation() async throws { throw LaunchError.managedBySteam }
    @MainActor override func _update() async throws { throw LaunchError.managedBySteam }

    enum LaunchError: LocalizedError {
        case clientMissing, payloadUnavailable, openFailed, managedBySteam
        var errorDescription: String? {
            switch self {
            case .clientMissing: "Install or open the native Steam client, then try Play again."
            case .payloadUnavailable: "The Mac game files are unavailable. Refresh the library or check the installation in Steam."
            case .openFailed: "macOS could not hand this game to Steam. Open Steam and try again."
            case .managedBySteam: "Manage this game's files in Steam."
            }
        }
    }
}
