import Foundation
import XCTest
import SmartTagCore
@testable import SmartTagDiagnostic

final class UWBHoppingAdmissionTests: XCTestCase {
    private func parameters(hopping: Bool) throws -> AppleUWBParameters {
        var bytes = try Data(hex: "020000001e5555785634120a0906006009f00003010203040506785614000000000001")
        bytes[34] = hopping ? 1 : 0
        return try AppleUWBProtocol.decodeShareable(bytes)
    }

    func testGrantedOffRequestForwardsSelectedOffPacketWithoutForcingAnotherFlag() throws {
        var sent: [Data] = []
        try UWBHoppingAdmission.prepareAndSend(parameters: parameters(hopping: false),
            accessoryAddress: 0x1234, requestedHopping: false) { sent.append($0) }
        XCTAssertEqual(sent.map(\.hex), ["002f0c9c0112345678123456780907d000f0030a0105004c0102030405060600000000"])
    }

    func testDefaultRequestAndAppleSelectedOnPreservePreviousPacket() throws {
        var sent: [Data] = []
        try UWBHoppingAdmission.prepareAndSend(parameters: parameters(hopping: true),
            accessoryAddress: 0x1234) { sent.append($0) }
        XCTAssertEqual(sent.map(\.hex), ["002f0c9c0512345678123456780907d000f0030a0105004c0102030405060600000000"])
    }

    func testOnRequestStillAllowsAppleToSelectOff() throws {
        var sent: [Data] = []
        try UWBHoppingAdmission.prepareAndSend(parameters: parameters(hopping: false),
            accessoryAddress: 0x1234, requestedHopping: true) { sent.append($0) }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?[4], 1)
    }

    func testDeniedOffRequestThrowsBeforeAnyBluetoothSend() throws {
        let selected = try parameters(hopping: true)
        var sends = 0
        XCTAssertThrowsError(try UWBHoppingAdmission.prepareAndSend(parameters: selected,
            accessoryAddress: 0x1234, requestedHopping: false) { _ in sends += 1 }) { error in
            XCTAssertEqual(error as? UWBHoppingAdmission.Failure, .notGranted)
            XCTAssertTrue(error.localizedDescription.lowercased().contains("solicitud no concedida"))
        }
        XCTAssertEqual(sends, 0)
    }

    func testVersionOneOffRequestIsRejectedBeforeEncodingOrSending() throws {
        let bytes = try Data(hex: "01000100195553785634120a0906006009f0000301020304050678561400")
        var sends = 0
        XCTAssertThrowsError(try UWBHoppingAdmission.prepareAndSend(parameters: AppleUWBProtocol.decodeShareable(bytes),
            accessoryAddress: 0x1234, requestedHopping: false) { _ in sends += 1 }) { error in
            XCTAssertEqual(error as? UWBHoppingAdmission.Failure, .unsupportedVersion)
        }
        XCTAssertEqual(sends, 0)
    }
}
