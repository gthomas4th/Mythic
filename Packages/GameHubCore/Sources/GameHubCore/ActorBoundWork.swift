import Foundation

/// Keeps UI-owned objects out of background work. Preparation happens when queued
/// work actually starts, after its dependencies; only successful work updates state.
public struct ActorBoundWork<Input: Sendable, Output: Sendable>: Sendable {
    public let prepare: @MainActor @Sendable () throws -> Input
    public let perform: @Sendable (Input) async throws -> Output
    public let apply: @MainActor @Sendable (Output) -> Void

    public init(prepare: @escaping @MainActor @Sendable () throws -> Input,
                perform: @escaping @Sendable (Input) async throws -> Output,
                apply: @escaping @MainActor @Sendable (Output) -> Void) {
        self.prepare = prepare
        self.perform = perform
        self.apply = apply
    }

    public func run() async throws {
        try Task.checkCancellation()
        let input = try await MainActor.run {
            try Task.checkCancellation()
            return try prepare()
        }
        let output = try await perform(input)
        try await MainActor.run {
            try Task.checkCancellation()
            apply(output)
        }
    }
}
