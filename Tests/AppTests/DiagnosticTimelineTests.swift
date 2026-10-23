import Foundation
import XCTest
@testable import SmartTagDiagnostic

@MainActor
final class DiagnosticTimelineTests: XCTestCase {
    private final class Clock { var now: TimeInterval = 100 }

    func testSameMonotonicOriginMakesSeparateClientLogsComparable() {
        let clock = Clock()
        let timeline = DiagnosticTimeline(origin: 100, now: { clock.now })
        let bluetooth = TagBluetoothClient(timeline: timeline)
        let nearby = NearbyInteractionClient(capabilityOverride: false, timeline: timeline)
        clock.now = 101.125
        bluetooth.sendUWBConfiguration(Data())
        clock.now = 103.75
        nearby.start(version: .v1, sendConfiguration: { _ in XCTFail() },
                     acceptDistance: { _ in XCTFail(); return nil }, onStop: {})
        XCTAssertTrue(bluetooth.events.first?.hasPrefix("[+1.125 s] ") == true)
        XCTAssertTrue(nearby.events.first?.hasPrefix("[+3.750 s] ") == true)
        XCTAssertNil(nearby.distanceMeters)
    }

    func testClearingOneBufferDoesNotResetTheSharedEpoch() {
        let clock = Clock()
        let timeline = DiagnosticTimeline(origin: 100, now: { clock.now })
        let bluetooth = TagBluetoothClient(timeline: timeline)
        let nearby = NearbyInteractionClient(capabilityOverride: false, timeline: timeline)
        bluetooth.sendUWBConfiguration(Data())
        bluetooth.clear()
        XCTAssertTrue(bluetooth.events.isEmpty)
        clock.now = 110
        bluetooth.sendUWBConfiguration(Data())
        clock.now = 111
        nearby.start(version: .v2, sendConfiguration: { _ in XCTFail() },
                     acceptDistance: { _ in XCTFail(); return nil }, onStop: {})
        XCTAssertTrue(bluetooth.events.first?.hasPrefix("[+10.000 s] ") == true)
        XCTAssertTrue(nearby.events.first?.hasPrefix("[+11.000 s] ") == true)
    }

    func testTerminalCauseIsLoggedBeforeCleanupAndCleanupRunsOnlyOnce() {
        let timeline = DiagnosticTimeline(origin: 10, now: { 12.5 })
        let client = NearbyInteractionClient(capabilityOverride: false, timeline: timeline)
        var observedDuringCleanup: String?
        var cleanupCount = 0
        client.start(version: .v1, sendConfiguration: { _ in XCTFail() },
                     acceptDistance: { _ in XCTFail(); return nil }, onStop: {
            cleanupCount += 1
            observedDuringCleanup = client.events.last
        })
        XCTAssertTrue(observedDuringCleanup?.contains("no admite medición precisa UWB") == true)
        XCTAssertTrue(observedDuringCleanup?.hasPrefix("[+2.500 s] ") == true)
        client.stop()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertNil(client.distanceMeters)
    }

    func testFormattingIsLocaleStableClampsInvalidClockAndDoesNotAlterMessage() {
        XCTAssertEqual(DiagnosticTimeline(origin: 2, now: { 3.125 }).stamp("Inicio"), "[+1.125 s] Inicio")
        XCTAssertEqual(DiagnosticTimeline(origin: 2, now: { 1 }).stamp("Cierre"), "[+0.000 s] Cierre")
        XCTAssertEqual(DiagnosticTimeline(origin: 2, now: { .nan }).stamp("Espera"), "[+0.000 s] Espera")
    }
}
