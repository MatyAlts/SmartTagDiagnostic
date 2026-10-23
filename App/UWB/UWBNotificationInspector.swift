import Foundation
import SmartTagCore

/// Inspects the established incoming encrypted frame, without interpreting UWB payloads.
enum UWBNotificationInspector {
    enum Result: Equatable {
        case accepted(payloadLength: Int)
        case invalidCiphertext
        case invalidFrame
        case replayRejected
    }

    static func inspect(ciphertext: Data, master: Data, tagNonce: Data,
                        replay: inout ReplayCounter) -> Result {
        let plaintext: Data
        do {
            let key = SmartTagCrypto.derive(master: master, context: tagNonce)
            plaintext = try SmartTagCrypto.decrypt(ciphertext, key: key, iv: tagNonce)
        } catch { return .invalidCiphertext }

        let frame: SmartTagFrame
        do { frame = try SmartTagFrame.decode(plaintext) }
        catch { return .invalidFrame }
        do { try replay.accept(frame.counter) }
        catch { return .replayRejected }
        return .accepted(payloadLength: frame.payload.count)
    }
}
