import XCTest
import SmartTagCore
@testable import SmartTagDiagnostic

@MainActor
final class NearbyInteractionClientTests: XCTestCase {
    func testUnsupportedDeviceRejectsBothProfilesWithoutSendingOrDistance() {
        for version in [AppleUWBVersion.v1, .v2] {
            let client = NearbyInteractionClient(capabilityOverride: false)
            var sends = 0
            var reads = 0
            var stops = 0
            client.start(version: version, sendConfiguration: { _ in sends += 1 },
                         acceptDistance: { value in reads += 1; return value },
                         onStop: { stops += 1 })
            XCTAssertFalse(client.supportsUWB)
            XCTAssertFalse(client.isRunning)
            XCTAssertNil(client.distanceMeters)
            XCTAssertNotNil(client.errorMessage)
            XCTAssertEqual(sends, 0)
            XCTAssertEqual(reads, 0)
            XCTAssertEqual(stops, 1)
            client.stop()
            client.stop()
            XCTAssertEqual(stops, 1)
        }
    }

    func testClearResetsFailureAndRepeatedAttemptsStopIndependently() {
        let client = NearbyInteractionClient(capabilityOverride: false)
        var stops = 0
        for _ in 0..<2 {
            client.start(version: .v1, sendConfiguration: { _ in XCTFail("Unexpected configuration") },
                         acceptDistance: { _ in XCTFail("Unexpected measurement"); return nil },
                         onStop: { stops += 1 })
            XCTAssertNotNil(client.errorMessage)
            client.clear()
            XCTAssertNil(client.errorMessage)
            XCTAssertNil(client.distanceMeters)
            XCTAssertFalse(client.isRunning)
            XCTAssertTrue(client.events.isEmpty)
        }
        XCTAssertEqual(stops, 2)
    }
}

