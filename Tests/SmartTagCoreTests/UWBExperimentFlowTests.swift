import Foundation
import XCTest
@testable import SmartTagCore

final class UWBExperimentFlowTests: XCTestCase {
    private let parameters = Data([0x01, 0x02, 0x03])

    private func starting() -> UWBExperimentFlow {
        var flow = UWBExperimentFlow()
        XCTAssertEqual(flow.receive(.authenticated), .none)
        XCTAssertEqual(flow.receive(.configuration(parameters)), .none)
        XCTAssertEqual(flow.receive(.subscribed), .writeStart)
        return flow
    }

    func testStartWaitsForAllGuardsAndConfigurationWaitsForStartAcknowledgement() {
        var flow = starting()
        XCTAssertEqual(flow.state, .starting)
        XCTAssertEqual(flow.receive(.subscribed), .none)
        XCTAssertEqual(flow.receive(.configurationAcknowledged), .none)
        XCTAssertEqual(flow.receive(.startAcknowledged), .writeConfiguration(parameters))
        XCTAssertEqual(flow.state, .configuring)
        XCTAssertNil(flow.receiveDistance(1.2))
        XCTAssertEqual(flow.receive(.startAcknowledged), .none)
        XCTAssertEqual(flow.receive(.configurationAcknowledged), .none)
        XCTAssertEqual(flow.state, .active)
        XCTAssertEqual(flow.receiveDistance(1.2), 1.2)
    }

    func testConfigurationArrivingLastCanStartButEmptyConfigurationCannot() {
        var flow = UWBExperimentFlow()
        XCTAssertEqual(flow.receive(.authenticated), .none)
        XCTAssertEqual(flow.receive(.subscribed), .none)
        XCTAssertEqual(flow.receive(.configuration(Data())), .none)
        XCTAssertEqual(flow.state, .preparing)
        XCTAssertEqual(flow.receive(.configuration(parameters)), .writeStart)
    }

    func testFailureOfStartStillAttemptsStopThenDisconnectsOnTimeout() {
        var flow = starting()
        XCTAssertEqual(flow.receive(.failure), .writeStop)
        XCTAssertEqual(flow.state, .stopping)
        XCTAssertEqual(flow.receive(.startAcknowledged), .none)
        XCTAssertEqual(flow.receive(.cancel), .none)
        XCTAssertEqual(flow.receive(.timeout), .disconnect)
        XCTAssertEqual(flow.state, .closed)
        XCTAssertEqual(flow.receive(.configuration(parameters)), .none)
        XCTAssertEqual(flow.receive(.authenticated), .none)
        XCTAssertNil(flow.receiveDistance(0.5))
    }

    func testCancellationBeforeStartDisconnectsWithoutStop() {
        var flow = UWBExperimentFlow()
        XCTAssertEqual(flow.receive(.authenticated), .none)
        XCTAssertEqual(flow.receive(.cancel), .disconnect)
        XCTAssertEqual(flow.receive(.subscribed), .none)
        XCTAssertEqual(flow.receive(.stopAcknowledged), .none)
        XCTAssertEqual(flow.state, .closed)
    }

    func testBackgroundStopsActiveSessionAndStopAcknowledgementCloses() {
        var flow = starting()
        _ = flow.receive(.startAcknowledged)
        _ = flow.receive(.configurationAcknowledged)
        XCTAssertEqual(flow.receiveDistance(0), 0)
        XCTAssertEqual(flow.receive(.background), .writeStop)
        XCTAssertNil(flow.lastDistance)
        XCTAssertEqual(flow.receive(.stopAcknowledged), .disconnect)
        XCTAssertEqual(flow.receive(.timeout), .none)
    }

    func testInvalidOrMissingMeasurementsClearDisplayedDistance() {
        var flow = starting()
        _ = flow.receive(.startAcknowledged)
        _ = flow.receive(.configurationAcknowledged)
        for invalid in [Double.nan, Double.infinity, -Double.infinity, -0.1] {
            XCTAssertEqual(flow.receiveDistance(2.4), 2.4)
            XCTAssertNil(flow.receiveDistance(invalid))
            XCTAssertNil(flow.lastDistance)
        }
        XCTAssertEqual(flow.receiveDistance(3.1), 3.1)
        XCTAssertNil(flow.receiveDistance(nil))
        XCTAssertNil(flow.lastDistance)
    }

    func testOutgoingCounterBeginsAtOneAndCountsEachEncryptedCommand() throws {
        var counter = UWBCommandCounter()
        XCTAssertEqual(try counter.frame(payload: Data([1])), Data([1, 0, 0, 0, 1]))
        XCTAssertEqual(try counter.frame(payload: parameters), Data([2, 0, 0, 0, 1, 2, 3]))
        XCTAssertEqual(try counter.frame(payload: Data([0])), Data([3, 0, 0, 0, 0]))
    }

    func testCounterUsesLittleEndianAndRefusesWraparound() throws {
        var counter = UWBCommandCounter(lastIssued: 255)
        XCTAssertEqual(try counter.frame(payload: Data([1])), Data([0, 1, 0, 0, 1]))
        var exhausted = UWBCommandCounter(lastIssued: UInt32.max - 1)
        XCTAssertEqual(try exhausted.frame(payload: Data([0])), Data([255, 255, 255, 255, 0]))
        XCTAssertThrowsError(try exhausted.frame(payload: Data([1])))
        XCTAssertThrowsError(try exhausted.frame(payload: Data([0])))
    }
}
