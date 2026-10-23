import XCTest
import Foundation
import SmartTagCore
@testable import SmartTagDiagnostic

/// Native bridge checks. Execution requires Xcode; these are not a substitute for live login tests.
final class AccountSecurityTests: XCTestCase {
    func testPBKDF2SHA256IndependentVector() throws {
        // RFC-style password/salt vector: PBKDF2-HMAC-SHA256, one iteration, dkLen 16.
        let key = try AccountSecurity.derive(password: "password", salt: Data("salt".utf8), iterations: 1)
        XCTAssertEqual(key, try Data(hex: "120fb6cffcf8b32c43e7225256c4f837"))
        XCTAssertNotEqual(try AccountSecurity.derive(password: "password", salt: Data("salt".utf8), iterations: 2), key)
    }

    func testECBMatchesFIPS197KnownFirstBlock() throws {
        let key = try Data(hex: "000102030405060708090a0b0c0d0e0f")
        let clear = try Data(hex: "00112233445566778899aabbccddeeff")
        let encrypted = try AccountSecurity.crypt(clear, key: key)
        // FIPS 197 AES-128 example; the following block carries PKCS7 padding.
        XCTAssertEqual(Data(encrypted.prefix(16)), try Data(hex: "69c4e0d86a7b0430d8cdb78070b4c55a"))
        XCTAssertEqual(encrypted.count, 32)
        XCTAssertEqual(try AccountSecurity.crypt(encrypted, key: key, decrypt: true), clear)
    }

    func testCBCMatchesNISTSP80038AFirstBlock() throws {
        let key = try Data(hex: "2b7e151628aed2a6abf7158809cf4f3c")
        let iv = try Data(hex: "000102030405060708090a0b0c0d0e0f")
        let clear = try Data(hex: "6bc1bee22e409f96e93d7e117393172a")
        let encrypted = try AccountSecurity.crypt(clear, key: key, iv: iv)
        XCTAssertEqual(Data(encrypted.prefix(16)), try Data(hex: "7649abac8119b246cee98e9b12e9197d"))
        XCTAssertEqual(try AccountSecurity.crypt(encrypted, key: key, iv: iv, decrypt: true), clear)
        XCTAssertThrowsError(try AccountSecurity.crypt(clear, key: key, iv: Data([0])))
    }

    func testEncryptedCallbackRoundTripUsesFirst16UTF8Bytes() throws {
        let state = "abcdefghijklmnopqrstuvwx"
        let key = Data(state.utf8.prefix(16))
        let clear = "https://account.samsung.com"
        let encrypted = try AccountSecurity.crypt(Data(clear.utf8), key: key)
        XCTAssertEqual(try AccountSecurity.decryptHex(encrypted.hex, key: state), clear)
        XCTAssertThrowsError(try AccountSecurity.decryptHex(encrypted.hex, key: "short"))
        XCTAssertThrowsError(try AccountSecurity.decryptHex(encrypted.hex, key: "xxxxxxxxxxxxxxxxxxxxxxxx"))
    }

    func testMalformedCallbackCiphertextRejected() {
        let key = "abcdefghijklmnop"
        for hex in ["", "0", "zz", "00", String(repeating: "a", count: 65538)] {
            XCTAssertThrowsError(try AccountSecurity.decryptHex(hex, key: key))
        }
    }

    func testMalformedSPKIRejectedWithoutWrapping() {
        for spki in [Data(), Data([0x30, 0x80]), Data([0x30, 0x03, 0x02, 0x01, 0x00])] {
            XCTAssertThrowsError(try AccountSecurity.rsaWrap(Data("test".utf8), spki: spki))
        }
    }
}
