import Foundation
import XCTest
import SmartTagCore
@testable import SmartTagDiagnostic

final class RingNotificationInspectorTests: XCTestCase {
    private let master = Data(repeating: 0x41, count: 16)
    private let nonce = Data(repeating: 0x18, count: 16)

    private func encrypted(_ payload: Data, counter: UInt32) throws -> Data {
        let key = SmartTagCrypto.derive(master: master, context: nonce)
        return try SmartTagCrypto.encrypt(SmartTagFrame(counter: counter, payload: payload).encoded,
                                         key: key, iv: nonce)
    }

    func testOnlyExactRingStatusesAndDocumentedCommandBytesAreAccepted() throws {
        XCTAssertEqual(RingNotificationInspector.characteristic, "DEE30001-182D-5496-B1AD-14F216324184")
        XCTAssertEqual(RingNotificationInspector.startPayload, Data([1]))
        XCTAssertEqual(RingNotificationInspector.stopPayload, Data([0]))
        var replay = ReplayCounter()
        for (counter, payload, expected) in [(UInt32(1), Data([1]), RingNotificationInspector.Result.accepted(isRinging: true)),
            (2, Data([0]), .accepted(isRinging: false)), (3, Data([2]), .unknownPayload), (4, Data([0, 1]), .unknownPayload)] {
            XCTAssertEqual(RingNotificationInspector.inspect(ciphertext: try encrypted(payload, counter: counter),
                master: master, tagNonce: nonce, replay: &replay), expected)
        }
    }

    func testStatusUsesBatterySharedReplayAndRejectsDuplicateOrOlderFrames() throws {
        var replay = ReplayCounter()
        try replay.accept(8)
        for (counter, expected) in [(UInt32(7), RingNotificationInspector.Result.replayRejected),
            (8, .replayRejected), (9, .accepted(isRinging: true)), (9, .replayRejected), (10, .accepted(isRinging: true))] {
            XCTAssertEqual(RingNotificationInspector.inspect(ciphertext: try encrypted(Data([1]), counter: counter),
                master: master, tagNonce: nonce, replay: &replay), expected)
        }
    }

    func testMalformedCiphertextPaddingAndFramesCannotProduceRingStatus() throws {
        var replay = ReplayCounter()
        for value in [Data(), Data([1]), Data(repeating: 0, count: 17)] {
            XCTAssertEqual(RingNotificationInspector.inspect(ciphertext: value,
                master: master, tagNonce: nonce, replay: &replay), .invalidCiphertext)
        }
        var damaged = try encrypted(Data(repeating: 0, count: 20), counter: 1)
        damaged[15] ^= 0xff
        XCTAssertEqual(RingNotificationInspector.inspect(ciphertext: damaged,
            master: master, tagNonce: nonce, replay: &replay), .invalidCiphertext)
        let key = SmartTagCrypto.derive(master: master, context: nonce)
        let shortFrame = try SmartTagCrypto.encrypt(Data([1, 2, 3]), key: key, iv: nonce)
        XCTAssertEqual(RingNotificationInspector.inspect(ciphertext: shortFrame,
            master: master, tagNonce: nonce, replay: &replay), .invalidFrame)
    }
}
