import Foundation

public struct CompatibilityProfile: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var profileID: String
    public var gameID: String
    public var runtimeID: String
    public var runtimeVersion: String
    public var rendererVersion: String
    public var updatePolicy = "manual"
    public var environment: [String: String]
    public var arguments: [String]
    public var validation: String
    public var notes: String

    public func validate() throws {
        guard schemaVersion == 1, Self.safeID(profileID), Self.safeID(runtimeID),
              gameID.hasPrefix("steam:"), SteamLaunch.url(appID: String(gameID.dropFirst(6))) != nil,
              updatePolicy == "manual", !runtimeVersion.isEmpty, !rendererVersion.isEmpty,
              ["testing", "owner-accepted"].contains(validation), notes.count <= 4096 else { throw ProfileError.invalid }
        let allowed: Set<String> = ["ROSETTA_ADVERTISE_AVX", "WINEMSYNC", "WINEESYNC", "MTL_HUD_ENABLED", "MTL_HUD_LOG_ENABLED", "D3DM_ENABLE_METALFX"]
        guard environment.allSatisfy({ allowed.contains($0.key) && ["0", "1"].contains($0.value) }),
              arguments.count <= 8, arguments.allSatisfy({ argument in
                  if argument == "-windowed" { return true }
                  for prefix in ["-ResX=", "-ResY="] where argument.hasPrefix(prefix) {
                      return Int(argument.dropFirst(prefix.count)).map { (480...3840).contains($0) } ?? false
                  }
                  return false
              }) else { throw ProfileError.invalid }
    }
    public static func safeID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
    public enum ProfileError: LocalizedError {
        case invalid, missingRollback
        public var errorDescription: String? {
            switch self {
            case .invalid: "The compatibility profile is invalid or uses unsupported settings."
            case .missingRollback: "No previous profile revision is available."
            }
        }
    }
}

/// Only metadata changes here; runtime directories and saves are never deleted or rewritten.
public struct CompatibilityProfileStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(_ id: String) throws -> CompatibilityProfile {
        guard CompatibilityProfile.safeID(id) else { throw CompatibilityProfile.ProfileError.invalid }
        return try decode(Data(contentsOf: directory.appendingPathComponent(id + ".json")))
    }
    public func decode(_ data: Data) throws -> CompatibilityProfile {
        guard data.count <= 64 * 1024 else { throw CompatibilityProfile.ProfileError.invalid }
        let profile = try JSONDecoder().decode(CompatibilityProfile.self, from: data)
        try profile.validate()
        return profile
    }
    public func save(_ profile: CompatibilityProfile) throws {
        try profile.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent(profile.profileID + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try decode(old)
            try old.write(to: directory.appendingPathComponent(profile.profileID + ".previous.json"), options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: file, options: .atomic)
    }
    public func rollback(_ id: String) throws {
        guard CompatibilityProfile.safeID(id) else { throw CompatibilityProfile.ProfileError.invalid }
        let previous = directory.appendingPathComponent(id + ".previous.json")
        guard FileManager.default.fileExists(atPath: previous.path) else { throw CompatibilityProfile.ProfileError.missingRollback }
        let profile = try decode(Data(contentsOf: previous))
        guard profile.profileID == id else { throw CompatibilityProfile.ProfileError.invalid }
        try save(profile)
    }
    public func clone(_ id: String, as newID: String) throws -> CompatibilityProfile {
        var profile = try load(id)
        profile.profileID = newID; profile.validation = "testing"
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent(newID + ".json").path) else { throw CompatibilityProfile.ProfileError.invalid }
        try save(profile)
        return profile
    }
}
