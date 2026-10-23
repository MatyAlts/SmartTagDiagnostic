import XCTest
@testable import SmartTagCore

final class BLEConnectionLifecycleTests: XCTestCase {
    func testImmediateRetryWaitsForNativeDisconnectThenAllowsSuccessfulReuse() throws {
        var lifecycle = BLEConnectionLifecycle()
        let first = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertEqual(lifecycle.state, .connecting)
        XCTAssertTrue(lifecycle.didConnect(generation: first))
        XCTAssertTrue(lifecycle.beginDisconnect(generation: first))
        XCTAssertEqual(lifecycle.state, .disconnecting)
        XCTAssertNil(lifecycle.beginConnection(), "A cancel request is not a completed disconnect")
        XCTAssertFalse(lifecycle.acceptsCallback(generation: first))
        XCTAssertTrue(lifecycle.didDisconnect(generation: first))
        XCTAssertEqual(lifecycle.state, .idle)

        let second = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(lifecycle.didConnect(generation: second))
        XCTAssertEqual(lifecycle.state, .connected)
        XCTAssertTrue(lifecycle.acceptsCallback(generation: second))
    }

    func testOldDisconnectCannotTerminateFreshAttempt() throws {
        var lifecycle = BLEConnectionLifecycle()
        let first = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertTrue(lifecycle.didDisconnect(generation: first))
        let second = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertTrue(lifecycle.didConnect(generation: second))

        XCTAssertFalse(lifecycle.didDisconnect(generation: first))
        XCTAssertEqual(lifecycle.currentGeneration, second)
        XCTAssertEqual(lifecycle.state, .connected)
        XCTAssertTrue(lifecycle.acceptsCallback(generation: second))
    }

    func testLatePeripheralCallbacksStayRejectedAfterSameDeviceRetry() throws {
        var lifecycle = BLEConnectionLifecycle()
        let first = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertTrue(lifecycle.acceptsCallback(generation: first))
        XCTAssertTrue(lifecycle.beginDisconnect(generation: first))
        XCTAssertFalse(lifecycle.acceptsCallback(generation: first))
        XCTAssertTrue(lifecycle.didDisconnect(generation: first))
        XCTAssertFalse(lifecycle.acceptsCallback(generation: first))

        let second = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertFalse(lifecycle.acceptsCallback(generation: first))
        XCTAssertTrue(lifecycle.acceptsCallback(generation: second))
        XCTAssertFalse(lifecycle.beginDisconnect(generation: first))
        XCTAssertEqual(lifecycle.state, .connecting)
    }

    func testConnectCompletionDuringCancellationCannotRestartDiscovery() throws {
        var lifecycle = BLEConnectionLifecycle()
        let generation = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertTrue(lifecycle.beginDisconnect(generation: generation))
        XCTAssertFalse(lifecycle.didConnect(generation: generation))
        XCTAssertEqual(lifecycle.state, .disconnecting)
        XCTAssertNil(lifecycle.beginConnection())
        XCTAssertTrue(lifecycle.didDisconnect(generation: generation))
        XCTAssertNotNil(lifecycle.beginConnection())
    }

    func testDuplicateCloseAndUnknownGenerationsCannotAdvanceLifecycle() throws {
        var lifecycle = BLEConnectionLifecycle()
        XCTAssertNil(lifecycle.currentGeneration)
        XCTAssertFalse(lifecycle.didDisconnect(generation: 1))
        XCTAssertFalse(lifecycle.acceptsCallback(generation: 1))
        let generation = try XCTUnwrap(lifecycle.beginConnection())
        XCTAssertFalse(lifecycle.didConnect(generation: generation + 1))
        XCTAssertTrue(lifecycle.didConnect(generation: generation))
        XCTAssertFalse(lifecycle.didConnect(generation: generation))
        XCTAssertTrue(lifecycle.beginDisconnect(generation: generation))
        XCTAssertFalse(lifecycle.beginDisconnect(generation: generation))
        XCTAssertTrue(lifecycle.didDisconnect(generation: generation))
        XCTAssertFalse(lifecycle.didDisconnect(generation: generation))
        XCTAssertEqual(lifecycle.state, .idle)
    }
}
