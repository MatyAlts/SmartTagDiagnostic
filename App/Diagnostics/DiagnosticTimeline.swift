import Foundation

/// Both log streams use one immutable process epoch, even when a buffer is cleared.
/// Only elapsed monotonic time is shown; no wall-clock date or device identity.
struct DiagnosticTimeline {
    static let process = DiagnosticTimeline(origin: ProcessInfo.processInfo.systemUptime)

    private let origin: TimeInterval
    private let now: () -> TimeInterval

    init(origin: TimeInterval, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.origin = origin
        self.now = now
    }

    func stamp(_ message: String) -> String {
        let delta = now() - origin
        let elapsed = delta.isFinite ? max(0, delta) : 0
        return String(format: "[+%.3f s] ", locale: Locale(identifier: "en_US_POSIX"), elapsed) + message
    }
}
