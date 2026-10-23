import Foundation
import XCTest
@testable import SmartTagDiagnostic

final class NITrialProgressTests: XCTestCase {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testSetupAndTransportDelayDoNotConsumeRangingWindowAfterActualAcknowledgement() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 100)
        XCTAssertEqual(progress.stage, .setup)
        XCTAssertEqual(progress.deadline, 130)
        XCTAssertTrue(progress.configurationGenerated(attemptID: first))
        XCTAssertEqual(progress.stage, .awaitingTransport)
        XCTAssertFalse(progress.acceptsMeasurements(attemptID: first, now: 120))
        XCTAssertTrue(progress.transportAcknowledged(attemptID: first, now: 129))
        XCTAssertEqual(progress.stage, .ranging)
        XCTAssertEqual(progress.deadline, 159)
        XCTAssertNil(progress.expiry(attemptID: first, now: 130))
        XCTAssertNil(progress.expiry(attemptID: first, now: 158.9))
        XCTAssertEqual(progress.expiry(attemptID: first, now: 159), .ranging)
    }

    func testEarlyStaleAndRepeatedAcknowledgementsCannotAdvanceOrExtendCurrentAttempt() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 0)
        XCTAssertFalse(progress.transportAcknowledged(attemptID: first, now: 2))
        XCTAssertEqual(progress.deadline, 30)
        XCTAssertFalse(progress.configurationGenerated(attemptID: second))
        XCTAssertTrue(progress.configurationGenerated(attemptID: first))
        XCTAssertFalse(progress.transportAcknowledged(attemptID: second, now: 5))
        XCTAssertTrue(progress.transportAcknowledged(attemptID: first, now: 8))
        XCTAssertEqual(progress.deadline, 38)
        XCTAssertFalse(progress.transportAcknowledged(attemptID: first, now: 20))
        XCTAssertEqual(progress.deadline, 38)

        progress.begin(attemptID: second, now: 50)
        XCTAssertFalse(progress.transportAcknowledged(attemptID: first, now: 51))
        XCTAssertNil(progress.expiry(attemptID: first, now: 100))
        XCTAssertEqual(progress.stage, .setup)
        XCTAssertEqual(progress.deadline, 80)
    }

    func testOnlyCurrentAcceptedRealMeasurementCancelsDeadline() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 0)
        XCTAssertNil(progress.receiveMeasurement(acceptedDistance: 2, attemptID: first, now: 0))
        XCTAssertTrue(progress.configurationGenerated(attemptID: first))
        XCTAssertTrue(progress.transportAcknowledged(attemptID: first, now: 1))
        XCTAssertNil(progress.receiveMeasurement(acceptedDistance: 2, attemptID: second, now: 2))
        for invalid in [Double.nan, Double.infinity, -Double.infinity, -1] {
            XCTAssertNil(progress.receiveMeasurement(acceptedDistance: invalid, attemptID: first, now: 2))
        }
        XCTAssertNil(progress.receiveMeasurement(acceptedDistance: nil, attemptID: first, now: 2))
        XCTAssertEqual(progress.deadline, 31)
        XCTAssertEqual(progress.receiveMeasurement(acceptedDistance: 0, attemptID: first, now: 2), 0)
        XCTAssertEqual(progress.stage, .measured)
        XCTAssertNil(progress.deadline)
        XCTAssertNil(progress.expiry(attemptID: first, now: 100))
        XCTAssertEqual(progress.receiveMeasurement(acceptedDistance: 1.25, attemptID: first, now: 101), 1.25)
    }

    func testAcknowledgementAtOrAfterSetupDeadlineCannotReviveExpiredAttempt() {
        for now in [30.0, 30.1, 60.0] {
            var progress = NITrialProgress()
            progress.begin(attemptID: first, now: 0)
            XCTAssertTrue(progress.configurationGenerated(attemptID: first))
            XCTAssertFalse(progress.transportAcknowledged(attemptID: first, now: now))
            XCTAssertEqual(progress.stage, .awaitingTransport)
            XCTAssertEqual(progress.deadline, 30)
            XCTAssertEqual(progress.expiry(attemptID: first, now: now), .setup)
        }
    }

    func testMeasurementAtOrAfterDeadlineIsRejectedEvenBeforeTimerCallbackRuns() {
        for now in [31.0, 31.1, 60.0] {
            var progress = NITrialProgress()
            progress.begin(attemptID: first, now: 0)
            XCTAssertTrue(progress.configurationGenerated(attemptID: first))
            XCTAssertTrue(progress.transportAcknowledged(attemptID: first, now: 1))
            XCTAssertFalse(progress.acceptsMeasurements(attemptID: first, now: now))
            XCTAssertNil(progress.receiveMeasurement(acceptedDistance: 2, attemptID: first, now: now))
            XCTAssertEqual(progress.stage, .ranging)
            XCTAssertEqual(progress.deadline, 31)
            XCTAssertEqual(progress.expiry(attemptID: first, now: now), .ranging)
        }
    }

    func testSetupExpiryIsDistinctFromRangingExpiry() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 0)
        XCTAssertNil(progress.expiry(attemptID: first, now: 29.9))
        XCTAssertEqual(progress.expiry(attemptID: first, now: 30), .setup)
        XCTAssertTrue(progress.configurationGenerated(attemptID: first))
        XCTAssertEqual(progress.expiry(attemptID: first, now: 30), .setup)
        XCTAssertNotEqual(NITrialProgress.Expiry.setup.message, NITrialProgress.Expiry.ranging.message)
        XCTAssertTrue(NITrialProgress.Expiry.setup.message.contains("app"))
        XCTAssertTrue(NITrialProgress.Expiry.ranging.message.contains("confirmación Bluetooth"))
        XCTAssertFalse(NITrialProgress.Expiry.ranging.message.contains("Nearby Interaction retiró"))
    }

    func testStopInvalidatesCallbacksAndNewAttemptResetsObservedRunningAndUpdates() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 0)
        XCTAssertTrue(progress.observedRunning(attemptID: first))
        XCTAssertFalse(progress.acceptsMeasurements(attemptID: first, now: 1))
        XCTAssertNil(progress.receiveMeasurement(acceptedDistance: 2, attemptID: first, now: 1))
        XCTAssertEqual(progress.deadline, 30)
        XCTAssertFalse(progress.observedRunning(attemptID: first))
        XCTAssertTrue(progress.observeUpdate(attemptID: first))
        progress.stop()
        XCTAssertEqual(progress.stage, .stopped)
        XCTAssertNil(progress.deadline)
        XCTAssertFalse(progress.configurationGenerated(attemptID: first))
        XCTAssertFalse(progress.transportAcknowledged(attemptID: first, now: 10))
        XCTAssertFalse(progress.observeUpdate(attemptID: first))
        XCTAssertNil(progress.receiveMeasurement(acceptedDistance: 1, attemptID: first, now: 10))
        progress.begin(attemptID: second, now: 20)
        XCTAssertFalse(progress.observedRunning(attemptID: first))
        XCTAssertTrue(progress.observedRunning(attemptID: second))
        XCTAssertEqual(progress.updateCount, 0)
    }

    func testUpdateDiagnosticsAreBoundedAndStaleUpdatesDoNotCount() {
        var progress = NITrialProgress()
        progress.begin(attemptID: first, now: 0)
        XCTAssertFalse(progress.observeUpdate(attemptID: second))
        XCTAssertEqual(progress.updateCount, 0)
        XCTAssertTrue(progress.observeUpdate(attemptID: first))
        XCTAssertTrue(progress.observeUpdate(attemptID: first))
        XCTAssertTrue(progress.observeUpdate(attemptID: first))
        XCTAssertFalse(progress.observeUpdate(attemptID: first))
        XCTAssertEqual(progress.updateCount, 4)
    }
}
