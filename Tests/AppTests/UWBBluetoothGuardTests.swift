import Foundation
import XCTest
@testable import SmartTagDiagnostic
import SmartTagCore

@MainActor
final class UWBBluetoothGuardTests: XCTestCase {
    func testNewClientCannotPublishUWBDistanceOrClaimActiveAuthentication() {
        let client = TagBluetoothClient()
        XCTAssertFalse(client.uwbReady)
        XCTAssertFalse(client.uwbActive)
        XCTAssertNil(client.acceptUWBDistance(1.5))
        XCTAssertNil(client.acceptUWBDistance(0))
        XCTAssertFalse(client.isBusy)
    }

    func testConfigurationWithoutAuthenticationFailsEvenWithValidPacket() throws {
        let client = TagBluetoothClient()
        let packet = try Data(hex: "002f0c9c0501020304112233440907d000f0030a0105004c0102030405060600000000")
        client.sendUWBConfiguration(packet)
        XCTAssertNotNil(client.errorMessage)
        XCTAssertFalse(client.uwbReady)
        XCTAssertFalse(client.uwbActive)
        XCTAssertFalse(client.isBusy)
        XCTAssertNil(client.acceptUWBDistance(2.3))
    }

    func testMalformedConfigurationWithoutSessionCannotStartOrLeaveBusyState() {
        for packet in [Data(), Data(repeating: 0, count: 34), Data(repeating: 0, count: 36)] {
            let client = TagBluetoothClient()
            client.sendUWBConfiguration(packet)
            XCTAssertNotNil(client.errorMessage)
            XCTAssertFalse(client.uwbReady)
            XCTAssertFalse(client.uwbActive)
            XCTAssertFalse(client.isBusy)
        }
    }

    func testStopAndClearAreIdempotentAndRejectLateMeasurements() {
        let client = TagBluetoothClient()
        client.stopUWB()
        client.stopUWB()
        XCTAssertFalse(client.uwbReady)
        XCTAssertFalse(client.uwbActive)
        XCTAssertNil(client.acceptUWBDistance(0.7))
        client.clear()
        XCTAssertNil(client.errorMessage)
        XCTAssertNil(client.battery)
        XCTAssertFalse(client.isBusy)
        XCTAssertFalse(client.uwbReady)
        XCTAssertFalse(client.uwbActive)
        XCTAssertNil(client.acceptUWBDistance(0.7))
    }
}
