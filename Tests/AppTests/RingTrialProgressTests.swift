import Foundation
import XCTest
@testable import SmartTagDiagnostic

final class RingTrialProgressTests: XCTestCase {
    private let trial = UUID()
    private let generation: UInt64 = 4

    private func starting(now: TimeInterval = 10) -> RingTrialProgress {
        var progress = RingTrialProgress()
        progress.begin(generation: generation, trialID: trial)
        XCTAssertEqual(progress.ready(generation: generation, trialID: trial), .writeStart)
        XCTAssertTrue(progress.startDispatched(now: now, generation: generation, trialID: trial))
        return progress
    }

    func testAutomaticStopStartsFiveSecondsAtDispatchNotLateAcknowledgement() {
        var progress = starting()
        XCTAssertEqual(progress.deadline, 15)
        XCTAssertEqual(progress.startWriteCompleted(success: true, generation: generation, trialID: trial), .none)
        XCTAssertEqual(progress.expiry(now: 14.999, generation: generation, trialID: trial), .none)
        XCTAssertEqual(progress.expiry(now: 15, generation: generation, trialID: trial), .writeStop)
        XCTAssertEqual(progress.phase, .stopping)
        XCTAssertNil(progress.deadline)
        XCTAssertEqual(progress.evidence, .unknown)
    }

    func testUnacknowledgedStartQueuesStopThenCompletionReleasesItEvenOnError() {
        for success in [true, false] {
            var progress = starting(now: 100)
            XCTAssertEqual(progress.expiry(now: 105, generation: generation, trialID: trial), .waitForStart)
            XCTAssertEqual(progress.requestStop(generation: generation, trialID: trial), .none)
            XCTAssertEqual(progress.startWriteCompleted(success: success, generation: generation, trialID: trial), .writeStop)
            XCTAssertEqual(progress.phase, .stopping)
            XCTAssertTrue(progress.stopDispatched(generation: generation, trialID: trial))
            XCTAssertEqual(progress.stopWriteCompleted(success: true, generation: generation, trialID: trial), .close)
            XCTAssertEqual(progress.evidence, .writeAcknowledged)
        }
    }

    func testManualStopAndFailedStartStillAttemptStopWithoutExtendingDeadline() {
        var manual = starting()
        XCTAssertEqual(manual.startWriteCompleted(success: true, generation: generation, trialID: trial), .none)
        XCTAssertFalse(manual.startDispatched(now: 14, generation: generation, trialID: trial))
        XCTAssertEqual(manual.deadline, 15)
        XCTAssertEqual(manual.requestStop(generation: generation, trialID: trial), .writeStop)
        XCTAssertEqual(manual.requestStop(generation: generation, trialID: trial), .none)
        XCTAssertEqual(manual.expiry(now: 15, generation: generation, trialID: trial), .none)
        var rejected = starting()
        XCTAssertEqual(rejected.startWriteCompleted(success: false, generation: generation, trialID: trial), .writeStop)
        XCTAssertEqual(rejected.evidence, .unknown)
    }

    func testNotificationAndTransportAcknowledgementAreDistinctAndCannotReviveStop() {
        var progress = starting()
        _ = progress.startWriteCompleted(success: true, generation: generation, trialID: trial)
        progress.observeStatus(isRinging: false, generation: generation, trialID: trial)
        XCTAssertEqual(progress.evidence, .unknown) // An initial OFF is not a response to STOP.
        _ = progress.requestStop(generation: generation, trialID: trial)
        XCTAssertTrue(progress.stopDispatched(generation: generation, trialID: trial))
        progress.observeStatus(isRinging: true, generation: generation, trialID: trial)
        XCTAssertEqual(progress.phase, .stopping)
        XCTAssertEqual(progress.evidence, .unknown)
        progress.observeStatus(isRinging: false, generation: generation, trialID: trial)
        XCTAssertEqual(progress.evidence, .notificationStopped)
        XCTAssertEqual(progress.phase, .stopping) // Do not confuse a pending write ACK.
        XCTAssertEqual(progress.stopWriteCompleted(success: true, generation: generation, trialID: trial), .close)
        XCTAssertEqual(progress.evidence, .notificationStopped)
    }

    func testStaleGenerationOrTrialCannotStopOrAcknowledgeCurrentRing() {
        var progress = starting()
        for (wrongGeneration, wrongTrial) in [(generation + 1, trial), (generation, UUID())] {
            XCTAssertEqual(progress.expiry(now: 20, generation: wrongGeneration, trialID: wrongTrial), .none)
            XCTAssertEqual(progress.requestStop(generation: wrongGeneration, trialID: wrongTrial), .none)
            XCTAssertEqual(progress.startWriteCompleted(success: true, generation: wrongGeneration, trialID: wrongTrial), .none)
            progress.observeStatus(isRinging: false, generation: wrongGeneration, trialID: wrongTrial)
            XCTAssertEqual(progress.phase, .starting)
            XCTAssertEqual(progress.deadline, 15)
        }
        XCTAssertEqual(progress.expiry(now: 20, generation: generation, trialID: trial), .waitForStart)
    }

    func testStoppingBeforeDispatchDoesNotSendStopAndUnexpectedLinkLossIsUnknown() {
        var preparing = RingTrialProgress()
        preparing.begin(generation: generation, trialID: trial)
        XCTAssertEqual(preparing.requestStop(generation: generation, trialID: trial), .close)
        XCTAssertEqual(preparing.evidence, .unknown)
        var active = starting()
        _ = active.startWriteCompleted(success: true, generation: generation, trialID: trial)
        active.connectionLost(generation: generation, trialID: trial)
        XCTAssertEqual(active.phase, .closed)
        XCTAssertEqual(active.evidence, .unknown)
        XCTAssertNil(active.deadline)
        XCTAssertEqual(active.expiry(now: 20, generation: generation, trialID: trial), .none)
    }

    func testFailedStopAcknowledgementCannotClaimCessation() {
        var progress = starting()
        _ = progress.startWriteCompleted(success: true, generation: generation, trialID: trial)
        _ = progress.requestStop(generation: generation, trialID: trial)
        XCTAssertTrue(progress.stopDispatched(generation: generation, trialID: trial))
        XCTAssertEqual(progress.stopWriteCompleted(success: false, generation: generation, trialID: trial), .close)
        XCTAssertEqual(progress.evidence, .unknown)
        XCTAssertEqual(progress.stopWriteCompleted(success: true, generation: generation, trialID: trial), .none)
    }
    func testStopEvidenceSurvivesMissingAckUnlessLaterAuthenticatedOnStatusArrives() {
        for laterOn in [false, true] {
            var progress = starting()
            _ = progress.startWriteCompleted(success: true, generation: generation, trialID: trial)
            _ = progress.requestStop(generation: generation, trialID: trial)
            _ = progress.stopDispatched(generation: generation, trialID: trial)
            progress.observeStatus(isRinging: false, generation: generation, trialID: trial)
            if laterOn { progress.observeStatus(isRinging: true, generation: generation, trialID: trial) }
            XCTAssertEqual(progress.phase, .stopping)
            XCTAssertEqual(progress.stopWriteCompleted(success: false, generation: generation, trialID: trial), .close)
            XCTAssertEqual(progress.evidence, laterOn ? .unknown : .notificationStopped)
        }
    }
}
