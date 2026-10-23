import Foundation
import SmartTagCore

/// Status bytes only; no sound volume read or write is part of this operation.
enum RingNotificationInspector {
    static let characteristic = "DEE30001-182D-5496-B1AD-14F216324184"
    static let startPayload = Data([1])
    static let stopPayload = Data([0])
    enum Result: Equatable {
        case accepted(isRinging: Bool), unknownPayload
        case invalidCiphertext, invalidFrame, replayRejected
    }

    static func inspect(ciphertext: Data, master: Data, tagNonce: Data,
                        replay: inout ReplayCounter) -> Result {
        let plaintext: Data
        do {
            let key = SmartTagCrypto.derive(master: master, context: tagNonce)
            plaintext = try SmartTagCrypto.decrypt(ciphertext, key: key, iv: tagNonce)
            // Same canonical PKCS7 check as the UWB inspector; this is not a MAC.
            let canonical = try SmartTagCrypto.encrypt(plaintext, key: key, iv: tagNonce)
            guard canonical.count == ciphertext.count,
                  zip(canonical, ciphertext).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else {
                return .invalidCiphertext
            }
        } catch { return .invalidCiphertext }
        let frame: SmartTagFrame
        do { frame = try SmartTagFrame.decode(plaintext) } catch { return .invalidFrame }
        do { try replay.accept(frame.counter) } catch { return .replayRejected }
        guard frame.payload.count == 1, let byte = frame.payload.first, byte <= 1 else { return .unknownPayload }
        return .accepted(isRinging: byte == 1)
    }
}
