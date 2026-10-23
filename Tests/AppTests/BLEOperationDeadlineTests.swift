import Foundation
import XCTest
@testable import SmartTagDiagnostic
import SmartTagCore

final class BLEOperationDeadlineTests: XCTestCase {
    func testReplacingRangingWithStopRejectsAlreadyResumedOldDeadline() {
        var deadline = BLEOperationDeadline()
        let ranging = deadline.arm(.rangingFallback, generation: 7, now: 100)
        let stop = deadline.arm(.stopAcknowledgement, generation: 7, now: 130)
        XCTAssertNil(deadline.consume(ranging, generation: 7, now: 135))
        XCTAssertNil(deadline.consume(stop, generation: 7, now: 132.999))
        XCTAssertEqual(deadline.consume(stop, generation: 7, now: 133), .stopAcknowledgement)
        XCTAssertNil(deadline.consume(stop, generation: 7, now: 134))
    }

    func testFallbackFirstStillAllowsSeparateStopAcknowledgementWindow() {
        var deadline = BLEOperationDeadline()
        let ranging = deadline.arm(.rangingFallback, generation: 8, now: 20)
        XCTAssertNil(deadline.consume(ranging, generation: 8, now: 50))
        XCTAssertEqual(deadline.consume(ranging, generation: 8, now: 55), .rangingFallback)
        let stop = deadline.arm(.stopAcknowledgement, generation: 8, now: 55)
        XCTAssertNil(deadline.consume(ranging, generation: 8, now: 56))
        XCTAssertNil(deadline.consume(stop, generation: 8, now: 57.999))
        XCTAssertEqual(deadline.consume(stop, generation: 8, now: 58), .stopAcknowledgement)
    }

    func testCancelledOrOtherGenerationCallbackCannotConsumeCurrentDeadline() {
        var deadline = BLEOperationDeadline()
        let cancelled = deadline.arm(.operation, generation: 1, now: 0)
        deadline.cancel()
        XCTAssertNil(deadline.consume(cancelled, generation: 1, now: 20))
        let current = deadline.arm(.operation, generation: 2, now: 20)
        XCTAssertNil(deadline.consume(current, generation: 1, now: 40))
        XCTAssertNil(deadline.consume(cancelled, generation: 2, now: 40))
        XCTAssertEqual(deadline.consume(current, generation: 2, now: 40), .operation)
    }

    func testScanWithoutConnectionCannotFireDuringConnectionAttempt() {
        var deadline = BLEOperationDeadline()
        let scan = deadline.arm(.scan, generation: nil, now: 5)
        XCTAssertNil(deadline.consume(scan, generation: 1, now: 17))
        XCTAssertEqual(deadline.consume(scan, generation: nil, now: 17), .scan)
        let disconnect = deadline.arm(.disconnect, generation: 3, now: 17)
        XCTAssertNil(deadline.consume(disconnect, generation: 3, now: 21.999))
        XCTAssertEqual(deadline.consume(disconnect, generation: 3, now: 22), .disconnect)
    }

    func testPendingWriteAndDispatchedStopHaveIndependentBoundedBudgets() {
        var deadline = BLEOperationDeadline()
        let queued = deadline.arm(.stopQueue, generation: 4, now: 10)
        XCTAssertEqual(queued.deadline, 13)
        let dispatched = deadline.arm(.stopAcknowledgement, generation: 4, now: 12.9)
        XCTAssertEqual(dispatched.deadline, 15.9, accuracy: 0.0001)
        XCTAssertNil(deadline.consume(queued, generation: 4, now: 13))
        XCTAssertNil(deadline.consume(dispatched, generation: 4, now: 15.899))
        XCTAssertEqual(deadline.consume(dispatched, generation: 4, now: 15.9), .stopAcknowledgement)
        let blocked = deadline.arm(.stopQueue, generation: 5, now: 30)
        XCTAssertEqual(deadline.consume(blocked, generation: 5, now: 33), .stopQueue)
    }

    func testRepeatedStopCannotReplaceOrExtendCurrentStopBudget() {
        var flow = UWBExperimentFlow()
        _ = flow.receive(.authenticated)
        _ = flow.receive(.subscribed)
        _ = flow.receive(.configuration(Data([1])))
        XCTAssertEqual(flow.receive(.cancel), .writeStop)
        var deadline = BLEOperationDeadline()
        let stop = deadline.arm(.stopAcknowledgement, generation: 9, now: 50)
        // The adapter arms only for writeStop, never for the no-op duplicate.
        XCTAssertEqual(flow.receive(.cancel), .none)
        XCTAssertEqual(deadline.consume(stop, generation: 9, now: 53), .stopAcknowledgement)
        XCTAssertEqual(flow.receive(.timeout), .disconnect)
        deadline.cancel()
        XCTAssertNil(deadline.consume(stop, generation: 9, now: 54))
        XCTAssertNil(flow.receiveDistance(1.2))
    }
}
