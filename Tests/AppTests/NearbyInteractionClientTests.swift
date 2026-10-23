import XCTest
import SmartTagCore
import NearbyInteraction
@testable import SmartTagDiagnostic

@MainActor
final class NearbyInteractionClientTests: XCTestCase {
    func testTransportAcknowledgementWithoutCurrentNISessionCannotStartMeasurements() {
        let client = NearbyInteractionClient(capabilityOverride: false)
        XCTAssertNil(client.attemptID)
        XCTAssertFalse(client.configurationAcknowledged(attemptID: UUID()))
        XCTAssertFalse(client.isRunning)
        XCTAssertNil(client.distanceMeters)
        client.stop()
        XCTAssertFalse(client.configurationAcknowledged(attemptID: UUID()))
    }

    func testAddressModeLabelsDescribeAnExperimentWithoutClaimingACompatibilityFix() {
        let modes: [SamsungUWBAddressMode] = [.baseline, .accessoryLittleEndian, .phoneLittleEndian, .bothLittleEndian]
        let labels = modes.map(NearbyInteractionClient.addressModeDescription)
        XCTAssertEqual(Set(labels).count, 4)
        XCTAssertTrue(labels[0].contains("Base"))
        XCTAssertTrue(labels[1].contains("etiqueta"))
        XCTAssertTrue(labels[2].contains("iPhone"))
        XCTAssertTrue(labels[3].contains("Ambas"))
        XCTAssertFalse(labels.joined().lowercased().contains("corregid"))
    }

    func testRemovalReasonsAndSessionPhasesAreDistinctAndSafe() {
        XCTAssertTrue(NearbyInteractionClient.removalDescription(.timeout).contains("timeout"))
        XCTAssertTrue(NearbyInteractionClient.removalDescription(.peerEnded).contains("peerEnded"))
        XCTAssertNotEqual(NearbyInteractionClient.removalDescription(.timeout),
                          NearbyInteractionClient.removalDescription(.peerEnded))
        let error = NSError(domain: "secret", code: -5887,
                            userInfo: [NSLocalizedDescriptionKey: "SECRET-RAW-CONFIG"])
        let message = NearbyInteractionClient.invalidationDescription(error, configurationSent: true)
        XCTAssertTrue(message.contains("-5887"))
        XCTAssertTrue(message.contains("después del envío"))
        XCTAssertFalse(message.contains("SECRET"))
        XCTAssertFalse(message.contains("secret"))
        XCTAssertTrue(NearbyInteractionClient.invalidationDescription(error, configurationSent: false)
            .contains("antes del envío"))
    }

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

