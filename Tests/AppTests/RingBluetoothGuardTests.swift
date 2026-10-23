import Foundation
import XCTest
import SmartTagCore
@testable import SmartTagDiagnostic

@MainActor
final class RingBluetoothGuardTests: XCTestCase {
    func testRingWithoutSelectedAuthenticatedCandidateCannotWriteOrPublishActive() throws {
        let client = TagBluetoothClient()
        let credentials = try TagCredentials(deviceID: "synthetic-test", masterSecret: Data(repeating: 1, count: 16), cipher: "AES/CBC/PKCS7Padding")
        client.startRing(candidateID: UUID(), credentials: credentials)
        XCTAssertNotNil(client.errorMessage)
        XCTAssertFalse(client.ringCanStop)
        XCTAssertFalse(client.isBusy)
        XCTAssertFalse(client.uwbReady)
        XCTAssertFalse(client.uwbActive)
        XCTAssertNil(client.acceptUWBDistance(1))
    }

    func testStopRingIsIdempotentWithoutSessionAndDoesNotInventStoppedConfirmation() {
        let client = TagBluetoothClient()
        client.stopRing()
        client.stopRing()
        XCTAssertFalse(client.ringCanStop)
        XCTAssertEqual(client.ringStatus, "Sin prueba de sonido")
        XCTAssertFalse(client.isBusy)
        XCTAssertTrue(client.events.isEmpty)
    }
}
