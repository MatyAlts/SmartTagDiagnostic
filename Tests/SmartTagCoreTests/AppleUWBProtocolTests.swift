import Foundation
import XCTest
@testable import SmartTagCore

final class AppleUWBProtocolTests: XCTestCase {
    func testAccessoryV1BootstrapVector() throws {
        let profile = UWBAccessoryProfile(version: .v1, accessoryAddress: 0x1234)
        let expected = try Data(hex: "01000000000000000000000000000015010001000000000000000000000000000134121400")
        XCTAssertEqual(try AppleUWBProtocol.accessoryData(profile: profile), expected)
        XCTAssertEqual(expected.count, 37)
    }

    func testAccessoryV2BootstrapVectorAndDeclaredIDs() throws {
        let profile = UWBAccessoryProfile(version: .v2, accessoryAddress: 0x1234,
                                         manufacturerID: 0x11223344, modelID: 0x55667788,
                                         middlewareVersion: 0x99aabbcc, maximumClockDrift: 30)
        let expected = try Data(hex: "01000000000000000000000000000020020000004433221188776655ccbbaa990134121e00000000000106006009f000")
        XCTAssertEqual(try AppleUWBProtocol.accessoryData(profile: profile), expected)
        XCTAssertEqual(expected.count, 48)
    }

    func testAccessoryProfileRejectsReservedAddressesAndInvalidClock() {
        for address in [UInt16(0), 0xffff] {
            XCTAssertThrowsError(try AppleUWBProtocol.accessoryData(profile:
                UWBAccessoryProfile(version: .v1, accessoryAddress: address)))
        }
        XCTAssertThrowsError(try AppleUWBProtocol.accessoryData(profile:
            UWBAccessoryProfile(version: .v2, accessoryAddress: 0x1234, maximumClockDrift: 0)))
    }

    func testDecodeV1ParametersUsesLittleEndianAndNoHopping() throws {
        let value = try AppleUWBProtocol.decodeShareable(v1())
        XCTAssertEqual(value, AppleUWBParameters(version: .v1, sessionID: 0x12345678,
            preamble: 10, channel: 9, slots: 6, slotDurationRSTU: 2400,
            intervalMilliseconds: 240, roundControl: 3, stsIV: Data([1, 2, 3, 4, 5, 6]),
            phoneAddress: 0x5678, maxClockDrift: 20, hopping: false))
    }

    func testDecodeV2ParametersAndHoppingSelection() throws {
        var bytes = try v2()
        XCTAssertTrue(try AppleUWBProtocol.decodeShareable(bytes).hopping)
        bytes[34] = 0
        let result = try AppleUWBProtocol.decodeShareable(bytes)
        XCTAssertEqual(result.version, .v2)
        XCTAssertFalse(result.hopping)
        XCTAssertEqual(result.phoneAddress, 0x5678)
    }

    func testDecodeRejectsLengthsAndUnsupportedVersions() throws {
        for length in [0, 4, 29, 31] {
            XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(Data(repeating: 0, count: length)))
        }
        let changes: [(Int, UInt8)] = [(0, 3), (2, 2), (4, 24)]
        for (offset, byte) in changes {
            var bytes = try v1(); bytes[offset] = byte
            XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(bytes))
        }
        var futureMinor = try v2(); futureMinor[2] = 1
        XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(futureMinor))
    }

    func testDecodeRejectsUnsupportedRadioParameters() throws {
        // These are deliberately outside the single-channel SmartTag trial profile.
        let changes: [(Int, UInt8)] = [(11, 8), (11, 13), (12, 5), (13, 5),
                                            (15, 0), (16, 0), (17, 0)]
        for (offset, byte) in changes {
            var bytes = try v1(); bytes[offset] = byte
            XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(bytes), "offset \(offset)")
        }
        for address in [[UInt8](repeating: 0, count: 2), [255, 255]] {
            var bytes = try v1(); bytes.replaceSubrange(26..<28, with: address)
            XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(bytes))
        }
    }

    func testDecodeRejectsNonzeroReservedBytesAndUnknownHopping() throws {
        for offset in 30..<34 {
            var bytes = try v2(); bytes[offset] = 1
            XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(bytes))
        }
        var bytes = try v2(); bytes[34] = 2
        XCTAssertThrowsError(try AppleUWBProtocol.decodeShareable(bytes))
    }

    private func v1() throws -> Data {
        try Data(hex: "01000100195553785634120a0906006009f0000301020304050678561400")
    }

    private func v2() throws -> Data {
        try Data(hex: "020000001e5553785634120a0906006009f00003010203040506785614000000000001")
    }
}
