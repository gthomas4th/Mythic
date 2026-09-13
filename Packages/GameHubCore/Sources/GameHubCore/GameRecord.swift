import Foundation

public enum ProviderID: String, Codable, Sendable { case steam, epic, local, emulator, xboxCloud, remotePC }
public struct GameIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let provider: ProviderID
    public let externalID: String
    public init(provider: ProviderID, externalID: String) { self.provider = provider; self.externalID = externalID }
    public var description: String { "\(provider.rawValue):\(externalID)" }
}
public struct GameRecord: Identifiable, Codable, Sendable {
    public let id: GameIdentity
    public let title: String
    public let launchTargets: [LaunchTarget]
    public let artwork: URL?
}
public struct LaunchTarget: Identifiable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case nativeMac, wineSteam, moonlight, emulator, webCloud }
    public let id: String
    public let kind: Kind
    public let locator: URL
    public let application: URL
    public var available: Bool = true
    public var verified: Bool = false
    public var profileID: String?
}
public protocol GameProvider: Sendable {
    var id: ProviderID { get }
    func discoverInstalled() async -> ProviderDiscovery
}
public enum SteamLaunch {
    public static func url(appID: String) -> URL? {
        guard let number = UInt32(appID), number > 0, String(number) == appID else { return nil }
        return URL(string: "steam://rungameid/\(number)")
    }
}

public struct ProviderDiscovery: Sendable {
    public let records: [GameRecord]
    public let diagnostics: [String]
}
