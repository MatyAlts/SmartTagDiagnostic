import Foundation

/// START/STOP transport ordering is separate from the accessory's reported status.
struct RingTrialProgress {
    enum Phase: Equatable { case idle, preparing, starting, active, stopping, closed }
    enum Action: Equatable { case none, writeStart, waitForStart, writeStop, close }
    enum Evidence: Equatable { case unknown, writeAcknowledged, notificationStopped }
    private(set) var phase: Phase = .idle
    private(set) var evidence: Evidence = .unknown
    private(set) var deadline: TimeInterval?
    private(set) var hasDispatchedStart = false
    private var generation: UInt64?
    private var trialID: UUID?
    private var startPending = false
    private var stopSent = false

    mutating func begin(generation: UInt64, trialID: UUID) {
        self = RingTrialProgress()
        self.generation = generation; self.trialID = trialID; phase = .preparing
    }
    private func current(_ generation: UInt64, _ trialID: UUID) -> Bool {
        self.generation == generation && self.trialID == trialID && phase != .closed
    }
    mutating func ready(generation: UInt64, trialID: UUID) -> Action {
        guard current(generation, trialID), phase == .preparing else { return .none }
        phase = .starting; startPending = true
        return .writeStart
    }
    mutating func startDispatched(now: TimeInterval, generation: UInt64, trialID: UUID) -> Bool {
        guard current(generation, trialID), phase == .starting, !hasDispatchedStart else { return false }
        hasDispatchedStart = true; deadline = now + 5
        return true
    }
    mutating func startWriteCompleted(success: Bool, generation: UInt64, trialID: UUID) -> Action {
        guard current(generation, trialID), startPending else { return .none }
        startPending = false
        if phase == .stopping { return .writeStop }
        guard success else { return requestStop(generation: generation, trialID: trialID) }
        phase = .active
        return .none
    }
    mutating func requestStop(generation: UInt64, trialID: UUID) -> Action {
        guard current(generation, trialID), phase != .stopping else { return .none }
        deadline = nil
        guard hasDispatchedStart else { phase = .closed; return .close }
        phase = .stopping
        return startPending ? .waitForStart : .writeStop
    }
    mutating func expiry(now: TimeInterval, generation: UInt64, trialID: UUID) -> Action {
        guard current(generation, trialID), let deadline, now >= deadline else { return .none }
        return requestStop(generation: generation, trialID: trialID)
    }
    mutating func stopDispatched(generation: UInt64, trialID: UUID) -> Bool {
        guard current(generation, trialID), phase == .stopping, !startPending, !stopSent else { return false }
        stopSent = true
        return true
    }
    mutating func stopWriteCompleted(success: Bool, generation: UInt64, trialID: UUID) -> Action {
        guard current(generation, trialID), phase == .stopping, stopSent else { return .none }
        if success && evidence != .notificationStopped { evidence = .writeAcknowledged }
        phase = .closed; deadline = nil
        return .close
    }
    mutating func observeStatus(isRinging: Bool, generation: UInt64, trialID: UUID) {
        guard current(generation, trialID) else { return }
        if isRinging { evidence = .unknown }
        else if stopSent { evidence = .notificationStopped }
    }
    mutating func connectionLost(generation: UInt64, trialID: UUID) {
        guard current(generation, trialID) else { return }
        phase = .closed; deadline = nil; evidence = .unknown
    }
}
