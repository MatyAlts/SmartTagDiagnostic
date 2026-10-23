import XCTest
import Foundation
import SmartTagCore
@testable import SmartTagDiagnostic

final class UWBNotificationInspectorTests: XCTestCase {
    private let master = Data(repeating: 0x42, count: 16)
    private let nonce = Data(repeating: 0x17, count: 16)

    private func encrypted(_ plaintext: Data) throws -> Data {
        try SmartTagCrypto.encrypt(plaintext,
            key: SmartTagCrypto.derive(master: master, context: nonce), iv: nonce)
    }

    func testSynthetic48ByteReplyReportsOnlyDecryptedPayloadLength() throws {
        var replay = ReplayCounter()
        let ciphertext = try encrypted(SmartTagFrame(counter: 7,
            payload: Data(repeating: 0xA5, count: 35)).encoded)
        XCTAssertEqual(ciphertext.count, 48)
        XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
            master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: 35))
    }

    func testDifferentPayloadLengthAndIncreasingCountersAreAccepted() throws {
        var replay = ReplayCounter()
        for (counter, length) in [(UInt32(20), 1), (UInt32(21), 17)] {
            let ciphertext = try encrypted(SmartTagFrame(counter: counter,
                payload: Data(repeating: 0x93, count: length)).encoded)
            XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: length))
        }
    }

    func testMalformedCiphertextAndShortDecryptedFramesAreDistinguished() throws {
        var replay = ReplayCounter()
        for length in [0, 1, 15, 17, 47] {
            XCTAssertEqual(UWBNotificationInspector.inspect(
                ciphertext: Data(repeating: 0, count: length),
                master: master, tagNonce: nonce, replay: &replay), .invalidCiphertext)
        }
        let validPadding = try encrypted(SmartTagFrame(counter: 7,
            payload: Data(repeating: 0xA5, count: 35)).encoded)
        // Reject an out-of-range final padding byte and inconsistent repeated padding.
        for index in [31, 30] {
            var invalidPadding = validPadding
            invalidPadding[index] ^= 0xFF
            XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: invalidPadding,
                master: master, tagNonce: nonce, replay: &replay), .invalidCiphertext)
        }
        XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: validPadding,
            master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: 35))
        for length in [0, 3, 4] {
            XCTAssertEqual(UWBNotificationInspector.inspect(
                ciphertext: try encrypted(Data(repeating: 0, count: length)),
                master: master, tagNonce: nonce, replay: &replay), .invalidFrame)
        }
    }

    func testBatteryAndNotificationsShareIncomingReplaySequence() throws {
        var replay = ReplayCounter()
        try replay.accept(8) // Counter already consumed by an authenticated battery response.
        let attempts: [(UInt32, UWBNotificationInspector.Result)] = [
            (7, .replayRejected), (8, .replayRejected),
            (9, .accepted(payloadLength: 1)), (9, .replayRejected),
            (10, .accepted(payloadLength: 1))]
        for (counter, expected) in attempts {
            let ciphertext = try encrypted(SmartTagFrame(counter: counter, payload: Data([0x44])).encoded)
            let result = UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay)
            XCTAssertEqual(result, expected)
        }
        XCTAssertThrowsError(try replay.accept(10))
        try replay.accept(11)
    }
}
