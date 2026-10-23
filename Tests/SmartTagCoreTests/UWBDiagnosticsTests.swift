import Foundation
import XCTest
@testable import SmartTagCore

final class UWBDiagnosticsTests: XCTestCase {
    func testBothKnownProfilesExposeOnlyStructuralAndRadioFields() throws {
        for hex in ["01000100195553785634120a0906006009f0000301020304050678561400",
                    "020000001e5553785634120b0906006009f00003010203040506785614000000000001"] {
            let data = try Data(hex: hex)
            let summary = UWBDiagnostics.shareableSummary(data).joined(separator: " ")
            XCTAssertTrue(summary.contains("canal 9"))
            XCTAssertTrue(summary.contains("2400 RSTU"))
            XCTAssertTrue(summary.contains("control 3"))
            for secret in ["12345678", "305419896", "5678", "22136", "010203040506", "STS", "dirección"] {
                XCTAssertFalse(summary.contains(secret), "Disclosed \(secret)")
            }
            XCTAssertFalse(summary.contains(hex))
        }
    }

    func testUnknownOrTruncatedLayoutsNeverDecodeRadioOffsets() throws {
        for bytes in [Data(), Data([2, 0, 0]), Data(repeating: 0x5a, count: 48)] {
            let summary = UWBDiagnostics.shareableSummary(bytes).joined(separator: " ")
            XCTAssertTrue(summary.contains("bytes"))
            XCTAssertFalse(summary.contains("canal"))
            XCTAssertFalse(summary.contains("5a5a"))
        }
    }

    func testDecodeAndTranslationFailuresHaveDistinctWhitelistedStages() {
        let apple = UWBDiagnostics.rejection(AppleUWBProtocolError.unsupportedRadioParameters, stage: .appleDecode)
        let samsung = UWBDiagnostics.rejection(SamsungUWBError.unsupportedProfile, stage: .samsungTranslation)
        XCTAssertTrue(apple.contains("decodificación Apple"))
        XCTAssertTrue(apple.contains("parámetros de radio"))
        XCTAssertTrue(samsung.contains("traducción Samsung"))
        XCTAssertNotEqual(apple, samsung)
        let unknown = NSError(domain: "secret-domain", code: 42, userInfo: [NSLocalizedDescriptionKey: "TOKEN-DO-NOT-LOG"])
        let safe = UWBDiagnostics.rejection(unknown, stage: .appleDecode)
        XCTAssertFalse(safe.contains("TOKEN"))
        XCTAssertFalse(safe.contains("secret-domain"))
    }

    func testTranslationSummaryNamesUnsupportedRadioFieldsWithoutIdentifiers() throws {
        let data = try Data(hex: "01000100195553785634120a0906006009f0000301020304050678561400")
        let valid = try AppleUWBProtocol.decodeShareable(data)
        XCTAssertEqual(UWBDiagnostics.unsupportedSamsungFields(valid, accessoryAddress: 0x1234), [])
        let changed = AppleUWBParameters(version: .v1, sessionID: valid.sessionID, preamble: 11,
            channel: 9, slots: 8, slotDurationRSTU: 3600, intervalMilliseconds: 240,
            roundControl: 1, stsIV: valid.stsIV, phoneAddress: valid.phoneAddress,
            maxClockDrift: 20, hopping: false)
        XCTAssertEqual(UWBDiagnostics.unsupportedSamsungFields(changed, accessoryAddress: 0x1234),
                       ["slots", "duración de slot", "control de ronda"])
    }
}
