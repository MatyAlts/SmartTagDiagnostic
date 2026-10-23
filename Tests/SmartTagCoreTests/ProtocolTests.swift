import XCTest
@testable import SmartTagCore

final class ProtocolTests: XCTestCase {
    let master = Data(0..<16)

    func testKDFVectors() throws {
        XCTAssertEqual(SmartTagCrypto.derive(master: master, context: Data("bleAuthentication".utf8)).hex, "f0e58cd5cd375f78094c304cb668aed4")
        XCTAssertEqual(SmartTagCrypto.derive(master: master, context: Data(16..<32)).hex, "9269d3751b18a2f960d6823ef2a2bb61")
    }

    func testCredentialsRejectUnknownCipherAndWrongKey() throws {
        XCTAssertThrowsError(try TagCredentials(deviceID: "tag", masterSecret: Data(), cipher: "AES/CBC/PKCS5Padding"))
        XCTAssertThrowsError(try TagCredentials(deviceID: "tag", masterSecret: master, cipher: "AES/GCM/NoPadding"))
        XCTAssertNoThrow(try TagCredentials(deviceID: "tag", masterSecret: master, cipher: "AES/CBC/PKCS5Padding"))
        XCTAssertNoThrow(try TagCredentials(deviceID: "tag", masterSecret: master, cipher: "AES/CBC/PKCS7PADDING"))
    }

    func testHexRejectsMalformedInput() throws {
        XCTAssertEqual(try Data(hex: "00ff10"), Data([0,255,16]))
        XCTAssertThrowsError(try Data(hex: "0"))
        XCTAssertThrowsError(try Data(hex: "xx"))
    }

    func testSupportedCipherDescriptorsUseOneCanonicalTransform() throws {
        for cipher in ["AES/CBC/PKCS5Padding", "aes/cbc/pkcs7padding",
                       "AES-CBC-PKCS5Padding", "aes-cbc-pkcs7padding",
                       "AES_128-CBC-PKCS5Padding", "aes_128-cbc-pkcs7padding"] {
            let credentials = try TagCredentials(deviceID: "fixture", masterSecret: master, cipher: cipher)
            XCTAssertEqual(credentials.cipher, "AES/CBC/PKCS7Padding", cipher)
            let nonce = Data(repeating: 7, count: 16)
            let proof = try SmartTagCrypto.encrypt(Data("smartthings".utf8), key: credentials.masterSecret, iv: nonce)
            XCTAssertNoThrow(try SmartTagCrypto.verifyProof(proof, key: credentials.masterSecret, phoneNonce: nonce))
        }
    }

    func testCipherDescriptorsRejectUnsupportedAndMalformedTransforms() {
        for cipher in ["", "AES", "AES-CBC", "AES_256-CBC-PKCS7Padding",
                       "AES-GCM-PKCS7Padding", "AES-ECB-PKCS7Padding", "AES-CBC-NoPadding",
                       "AES-AES-CBC-PKCS7Padding", "AES_128_128-CBC-PKCS7Padding",
                       "-AES-CBC-PKCS7Padding", "AES-CBC-PKCS7Padding-",
                       "AES--CBC-PKCS7Padding", "AES_128-CBC-PKCS7Padding-extra",
                       "AES/CBC/PKCS7Padding/", " AES-CBC-PKCS7Padding", "unknown"] {
            XCTAssertThrowsError(try TagCredentials(deviceID: "fixture", masterSecret: master, cipher: cipher), cipher) { error in
                guard case TagProtocolError.unsupportedCipher = error else {
                    return XCTFail("Expected unsupported cipher")
                }
            }
        }
    }

    func testAESKnownVectorAndMalformedCiphertext() throws {
        let key = try Data(hex: "2b7e151628aed2a6abf7158809cf4f3c")
        let iv = try Data(hex: "000102030405060708090a0b0c0d0e0f")
        let plaintext = try Data(hex: "6bc1bee22e409f96e93d7e117393172a")
        let encrypted = try SmartTagCrypto.encrypt(plaintext, key: key, iv: iv)
        XCTAssertEqual(encrypted.prefix(16).hex, "7649abac8119b246cee98e9b12e9197d")
        XCTAssertEqual(try SmartTagCrypto.decrypt(encrypted, key: key, iv: iv), plaintext)
        XCTAssertThrowsError(try SmartTagCrypto.decrypt(Data([0]), key: key, iv: iv))
    }

    func testProofRequiresExactPlaintext() throws {
        let nonce = Data(repeating: 7, count: 16)
        let proof = try SmartTagCrypto.encrypt(Data("smartthings".utf8), key: master, iv: nonce)
        XCTAssertNoThrow(try SmartTagCrypto.verifyProof(proof, key: master, phoneNonce: nonce))
        let wrong = try SmartTagCrypto.encrypt(Data("smartthings-extra".utf8), key: master, iv: nonce)
        XCTAssertThrowsError(try SmartTagCrypto.verifyProof(wrong, key: master, phoneNonce: nonce))
        XCTAssertThrowsError(try SmartTagCrypto.verifyProof(proof, key: master, phoneNonce: Data(repeating: 8, count: 16)))
    }

    func testFramesAndReplayProtection() throws {
        XCTAssertEqual(SmartTagFrame(counter: 0x12345678, payload: Data([3])).encoded.hex, "7856341203")
        XCTAssertEqual(try SmartTagFrame.decode(Data([1,0,0,0,2])).payload, Data([2]))
        XCTAssertThrowsError(try SmartTagFrame.decode(Data([0,0,0,0])))
        var counter = ReplayCounter()
        XCTAssertNoThrow(try counter.accept(0))
        XCTAssertNoThrow(try counter.accept(1))
        XCTAssertThrowsError(try counter.accept(1))
        XCTAssertThrowsError(try counter.accept(0))
    }

    func testBatteryIsDiscreteAndRejectsExtraBytes() throws {
        XCTAssertEqual(try BatteryLevel.decode(Data([0])), .veryLow)
        XCTAssertEqual(try BatteryLevel.decode(Data([3])), .full)
        XCTAssertThrowsError(try BatteryLevel.decode(Data([4])))
        XCTAssertThrowsError(try BatteryLevel.decode(Data([1,2])))
    }

    func testHandshakeAllowsEitherNonceArrivalOrder() throws {
        for notificationFirst in [false, true] {
            var state = AuthenticationProgress()
            XCTAssertEqual(try state.receive(notificationFirst ? .tagNonce : .nonceWritten), .wait)
            XCTAssertEqual(try state.receive(notificationFirst ? .nonceWritten : .tagNonce), .sendProof)
        }
    }

    func testHandshakeRequiresBothProofEventsInEitherOrder() throws {
        for notificationFirst in [false, true] {
            var state = AuthenticationProgress()
            _ = try state.receive(.nonceWritten); _ = try state.receive(.tagNonce)
            XCTAssertEqual(try state.receive(notificationFirst ? .proofVerified : .proofWritten), .wait)
            XCTAssertEqual(try state.receive(notificationFirst ? .proofWritten : .proofVerified), .readBattery)
            XCTAssertThrowsError(try state.receive(.proofVerified))
        }
    }

    func testEarlyProofAndDuplicateNonceStopHandshake() throws {
        var early = AuthenticationProgress()
        XCTAssertThrowsError(try early.receive(.proofVerified))
        XCTAssertThrowsError(try early.receive(.tagNonce))
        var duplicate = AuthenticationProgress()
        _ = try duplicate.receive(.tagNonce)
        XCTAssertThrowsError(try duplicate.receive(.tagNonce))
    }

    func testCancelledHandshakeCannotProduceCommands() throws {
        var state = AuthenticationProgress()
        _ = try state.receive(.nonceWritten)
        state.cancel()
        XCTAssertThrowsError(try state.receive(.tagNonce))
        state = AuthenticationProgress()
        XCTAssertEqual(try state.receive(.tagNonce), .wait)
    }
}
