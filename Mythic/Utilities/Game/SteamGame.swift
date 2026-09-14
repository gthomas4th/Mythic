// Copyright © 2023-2025 vapidinfinity; Game Hub contributors
import Foundation
import AppKit

/// Temporary bridge into the existing UI. Steam records never enter the legacy defaults blob.
@Observable final class SteamGame: Game {
    var record: GameRecord?
    var preferredTargetID: String?
    override var storefront: Storefront? { .steam }
    override var locationLabel: String? {
        guard let record else { return nil }
        let target = record.launchTargets.first { $0.id == preferredTargetID && $0.kind == .moonlight }
            ?? LaunchResolver.resolve(record.launchTargets, preferredID: preferredTargetID)
        guard let target else { return nil }
        return target.kind == .moonlight ? "PC" : "Local"
    }
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
        guard let record else { throw GameHubRuntime.RuntimeError.unconfigured }
        // An explicit Home PC choice must be checked before availability-based fallback.
        let preferredRemote = record.launchTargets.first { $0.id == preferredTargetID && $0.kind == .moonlight }
        guard let target = preferredRemote ?? LaunchResolver.resolve(record.launchTargets, preferredID: preferredTargetID) else {
            throw GameHubRuntime.RuntimeError.unconfigured
        }
        if target.kind == .moonlight {
            guard await HubConnections.shared.checkReachability() else { throw LaunchError.remoteUnavailable }
            try Task.checkCancellation()
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
        case clientMissing, payloadUnavailable, openFailed, managedBySteam, remoteUnavailable
        var errorDescription: String? {
            switch self {
            case .remoteUnavailable: "Your Home PC is unavailable. Turn it on and check Sunshine, or choose another target with Play using."
            case .clientMissing: "Install or open the native Steam client, then try Play again."
            case .payloadUnavailable: "The Mac game files are unavailable. Refresh the library or check the installation in Steam."
            case .openFailed: "macOS could not hand this game to Steam. Open Steam and try again."
            case .managedBySteam: "Manage this game's files in Steam."
            }
        }
    }
}
