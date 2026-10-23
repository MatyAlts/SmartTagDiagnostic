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
            master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: 35, comparison: .notAvailable))
    }

    func testDifferentPayloadLengthAndIncreasingCountersAreAccepted() throws {
        var replay = ReplayCounter()
        for (counter, length) in [(UInt32(20), 1), (UInt32(21), 17)] {
            let ciphertext = try encrypted(SmartTagFrame(counter: counter,
                payload: Data(repeating: 0x93, count: length)).encoded)
            XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: length, comparison: .notAvailable))
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
            master: master, tagNonce: nonce, replay: &replay), .accepted(payloadLength: 35, comparison: .notAvailable))
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
            (9, .accepted(payloadLength: 1, comparison: .notAvailable)), (9, .replayRejected),
            (10, .accepted(payloadLength: 1, comparison: .notAvailable))]
        for (counter, expected) in attempts {
            let ciphertext = try encrypted(SmartTagFrame(counter: counter, payload: Data([0x44])).encoded)
            let result = UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay)
            XCTAssertEqual(result, expected)
        }
        XCTAssertThrowsError(try replay.accept(10))
        try replay.accept(11)
    }

    func testExactSentConfigurationMatchesOnlyIdenticalPayload() throws {
        let expected = Data((0..<35).map { UInt8($0) })
        var changed = expected
        changed[19] ^= 1
        let attempts: [(Data, UWBNotificationInspector.Comparison)] = [
            (expected, .matches), (changed, .different), (Data(expected.dropLast()), .different)]
        var replay = ReplayCounter()
        for (index, attempt) in attempts.enumerated() {
            let (payload, comparison) = attempt
            let ciphertext = try encrypted(SmartTagFrame(counter: UInt32(index + 1), payload: payload).encoded)
            XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay, expectedConfiguration: expected),
                .accepted(payloadLength: payload.count, comparison: comparison))
        }
    }

    func testMissingOrInvalidExpectedConfigurationCannotClaimMatch() throws {
        var replay = ReplayCounter()
        let payload = Data(repeating: 0x25, count: 35)
        let expectedValues: [Data?] = [nil, Data(), Data(payload.dropLast()), payload + Data([0])]
        for (index, expected) in expectedValues.enumerated() {
            let ciphertext = try encrypted(SmartTagFrame(counter: UInt32(index + 1), payload: payload).encoded)
            XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
                master: master, tagNonce: nonce, replay: &replay, expectedConfiguration: expected),
                .accepted(payloadLength: 35, comparison: .notAvailable))
        }
    }

    func testMatchingPayloadStillRequiresFreshIncomingCounter() throws {
        let expected = Data(repeating: 0x31, count: 35)
        let ciphertext = try encrypted(SmartTagFrame(counter: 12, payload: expected).encoded)
        var replay = ReplayCounter()
        XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
            master: master, tagNonce: nonce, replay: &replay, expectedConfiguration: expected),
            .accepted(payloadLength: 35, comparison: .matches))
        XCTAssertEqual(UWBNotificationInspector.inspect(ciphertext: ciphertext,
            master: master, tagNonce: nonce, replay: &replay, expectedConfiguration: expected), .replayRejected)
    }
}
