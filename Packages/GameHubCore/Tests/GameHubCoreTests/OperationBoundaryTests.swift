import Foundation
import XCTest
@testable import GameHubCore

@MainActor final class OperationBoundaryTests: XCTestCase {
    final class State {
        var current = 0
        var prepared = false
        var applied = false
    }
    enum Failure: Error { case synthetic }

    func testSuccessfulWorkUsesLatestStateAndAppliesOnMainActor() async throws {
        let state = State()
        let work = ActorBoundWork(prepare: {
            MainActor.preconditionIsolated()
            return state.current
        }, perform: { value in
            XCTAssertFalse(Thread.isMainThread)
            return value + 1
        }, apply: { value in
            MainActor.preconditionIsolated()
            state.current = value
        })
        // Simulates an earlier queue dependency updating the game after enqueue.
        state.current = 41
        try await work.run()
        XCTAssertEqual(state.current, 42)
    }

    func testFailedWorkDoesNotApplyState() async {
        let state = State()
        let work = ActorBoundWork<Int, Int>(prepare: { state.current }, perform: { _ in
            throw Failure.synthetic
        }, apply: { _ in state.applied = true })
        do { try await work.run(); XCTFail("Expected worker failure") } catch is Failure {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(state.applied)
    }

    func testPreparationFailureDoesNotRunWorker() async {
        let state = State()
        let work = ActorBoundWork<Int, Int>(prepare: { throw Failure.synthetic }, perform: { _ in
            XCTFail("Worker must not run after preparation fails")
            return 1
        }, apply: { _ in state.applied = true })
        do { try await work.run(); XCTFail("Expected preparation failure") } catch is Failure {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(state.applied)
    }

    func testCancellationBeforeStartDoesNotPrepareOrApply() async {
        let state = State()
        let work = ActorBoundWork(prepare: { state.prepared = true; return 1 }, perform: { $0 },
                                  apply: { _ in state.applied = true })
        let task = Task { try await work.run() }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(state.prepared)
        XCTAssertFalse(state.applied)
    }

    func testCancellationAfterWorkDoesNotApplyState() async {
        let state = State()
        let work = ActorBoundWork(prepare: { 1 }, perform: { value in
            withUnsafeCurrentTask { $0?.cancel() }
            return value
        }, apply: { _ in state.applied = true })
        let task = Task { try await work.run() }
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(state.applied)
    }
}

final class LegendaryInstallMetadataTests: XCTestCase {
    func testFractionalInstallSizeAndPackCollection() {
        var metadata = LegendaryInstallMetadata()
        XCTAssertTrue(metadata.consume("[cli] Install size: 1.50 MiB", isStandardError: true))
        XCTAssertEqual(metadata.installSize, 1_572_864)
        XCTAssertFalse(metadata.consume("  * english - English voices", isStandardError: false))
        XCTAssertFalse(metadata.consume("  * music - Extra music", isStandardError: false))
        XCTAssertTrue(metadata.consume("Please enter tags of pack(s) to install", isStandardError: false))
        XCTAssertEqual(metadata.optionalPacks, ["english": "English voices", "music": "Extra music"])
    }
    func testMalformedSizeAndWrongStreamDoNotComplete() {
        var metadata = LegendaryInstallMetadata()
        for line in ["Install size: NaN MiB", "Install size: -1 MiB", "Install size: 99999999999999999999 MiB", "unrelated"] {
            XCTAssertFalse(metadata.consume(line, isStandardError: true))
        }
        XCTAssertFalse(metadata.consume("Install size: 2.0 MiB", isStandardError: false))
        XCTAssertNil(metadata.installSize)
        XCTAssertTrue(metadata.optionalPacks.isEmpty)
    }
}
