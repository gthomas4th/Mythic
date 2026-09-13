// Copyright © 2023-2025 vapidinfinity; Game Hub contributors
import Foundation
import AppKit

/// Temporary bridge into the existing UI. Steam records never enter the legacy defaults blob.
final class SteamGame: Game {
    override var storefront: Storefront? { .steam }
    override var supportsFileManagement: Bool { false }
    override var supportsLaunchArguments: Bool { false }
    override func getSupportedPlatforms() -> Set<Game.Platform>? { [.macOS] }

    init(record: GameRecord, target: LaunchTarget) {
        super.init(id: record.id.description, title: record.title,
                   installationState: .installed(location: target.application, platform: .macOS))
        _verticalImageURL = record.artwork
    }
    required init(from decoder: any Decoder) throws { try super.init(from: decoder) }

    @MainActor override func _launch() async throws {
        guard id.hasPrefix("steam:"),
              let url = SteamLaunch.url(appID: String(id.dropFirst(6))),
              case .installed(let location, _) = installationState,
              SteamNativeProvider.nativeApplication(in: location) != nil else {
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
