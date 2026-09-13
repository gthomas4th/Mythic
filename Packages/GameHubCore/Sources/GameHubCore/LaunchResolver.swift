import Foundation

public enum LaunchResolver {
    public static func resolve(_ targets: [LaunchTarget], preferredID: String? = nil) -> LaunchTarget? {
        let available = targets.filter(\.available)
        if let preferredID, let preferred = available.first(where: { $0.id == preferredID }) { return preferred }
        func rank(_ target: LaunchTarget) -> Int {
            switch target.kind {
            case .nativeMac: 0
            case .wineSteam: target.verified ? 1 : 5
            case .moonlight: 2
            case .emulator: 3
            case .webCloud: 4
            }
        }
        return available.sorted { (rank($0), $0.id) < (rank($1), $1.id) }.first
    }
    public static func merge(_ records: [GameRecord]) -> [GameRecord] {
        var result: [GameIdentity: GameRecord] = [:]
        for record in records {
            let previous = result[record.id]
            var targets = Dictionary((previous?.launchTargets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { existing, _ in existing })
            for target in record.launchTargets { targets[target.id] = target }
            result[record.id] = GameRecord(id: record.id, title: record.title,
                launchTargets: targets.values.sorted { $0.id < $1.id }, artwork: record.artwork ?? previous?.artwork)
        }
        return result.values.sorted { $0.id.description < $1.id.description }
    }
}
