import Foundation
import XCTest
@testable import SmartTagCore

final class SamsungUWBProtocolTests: XCTestCase {
    private func parameters(sessionID: UInt32 = 0x01020304, preamble: UInt8 = 10,
                            channel: UInt8 = 9, slots: UInt16 = 6,
                            slotDurationRSTU: UInt16 = 2400, interval: UInt16 = 240,
                            roundControl: UInt8 = 3,
                            iv: Data = Data([1, 2, 3, 4, 5, 6]),
                            phoneAddress: UInt16 = 0x3344, hopping: Bool = true) -> AppleUWBParameters {
        AppleUWBParameters(version: .v2, sessionID: sessionID, preamble: preamble,
            channel: channel, slots: slots, slotDurationRSTU: slotDurationRSTU,
            intervalMilliseconds: interval, roundControl: roundControl, stsIV: iv,
            phoneAddress: phoneAddress, maxClockDrift: 20, hopping: hopping)
    }

    func testHoppingVectorUsesBigEndianAddressesAppleVendorAndSamsungSlotMapping() throws {
        let result = try SamsungUWBProtocol.configuration(parameters: parameters(), accessoryAddress: 0x1122)
        let expected = try Data(hex: "002f0c9c0501020304112233440907d000f0030a0105004c0102030405060600000000")
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.count, 35)
    }

    func testNoHoppingVectorPreservesOtherProfileBitsAndDifferentInterval() throws {
        let input = parameters(sessionID: 0xaabbccdd, preamble: 12, interval: 120,
                               iv: Data(repeating: 0, count: 6), phoneAddress: 0xbeef, hopping: false)
        let expected = try Data(hex: "002f0c9c01aabbccddcafebeef0907d00078030c0105004c0000000000000600000000")
        XCTAssertEqual(try SamsungUWBProtocol.configuration(parameters: input, accessoryAddress: 0xcafe), expected)
    }

    func testRadioProfileRejectsUnsupportedChannelsPreamblesSlotsAndRoundControl() {
        let invalid = [parameters(channel: 5), parameters(channel: 10),
                       parameters(preamble: 8), parameters(preamble: 13),
                       parameters(slots: 0), parameters(slots: 7),
                       parameters(roundControl: 0), parameters(roundControl: 7)]
        for input in invalid {
            XCTAssertThrowsError(try SamsungUWBProtocol.configuration(parameters: input, accessoryAddress: 0x1122))
        }
    }

    func testOnlyExplicitSourceTimingMappingIsAccepted() {
        for duration in [UInt16(0), 2000, 2399, 2401] {
            XCTAssertThrowsError(try SamsungUWBProtocol.configuration(
                parameters: parameters(slotDurationRSTU: duration), accessoryAddress: 0x1122))
        }
        XCTAssertThrowsError(try SamsungUWBProtocol.configuration(parameters: parameters(interval: 0), accessoryAddress: 0x1122))
    }

    func testRejectsReservedOrCollidingAddressesAndZeroSession() {
        for address in [UInt16(0), 0xffff, 0x3344] {
            XCTAssertThrowsError(try SamsungUWBProtocol.configuration(parameters: parameters(), accessoryAddress: address))
        }
        for address in [UInt16(0), 0xffff] {
            XCTAssertThrowsError(try SamsungUWBProtocol.configuration(
                parameters: parameters(phoneAddress: address), accessoryAddress: 0x1122))
        }
        XCTAssertThrowsError(try SamsungUWBProtocol.configuration(parameters: parameters(sessionID: 0), accessoryAddress: 0x1122))
    }

    func testRequiresExactlySixSTSBytes() {
        for length in [0, 5, 7] {
            XCTAssertThrowsError(try SamsungUWBProtocol.configuration(
                parameters: parameters(iv: Data(repeating: 0, count: length)), accessoryAddress: 0x1122))
        }
    }
}
