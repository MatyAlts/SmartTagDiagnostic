import Foundation

/// Foreground experiment ordering. Platform adapters own timeouts and session identity.
/// Configuration bytes must already have passed the Samsung configuration codec.
public struct UWBExperimentFlow {
    public enum State: Equatable {
        case preparing, starting, configuring, active, stopping, closed
    }
    public enum Event {
        case authenticated, subscribed, configuration(Data)
        case startAcknowledged, configurationAcknowledged, stopAcknowledged
        case failure, cancel, background, timeout
    }
    public enum Action: Equatable {
        case none, writeStart, writeConfiguration(Data), writeStop, disconnect
    }

    public private(set) var state: State = .preparing
    public private(set) var lastDistance: Double?
    private var authenticated = false
    private var subscribed = false
    private var configuration: Data?

    public init() {}

    public mutating func receive(_ event: Event) -> Action {
        guard state != .closed else { return .none }
        if state == .stopping {
            switch event {
            case .stopAcknowledged, .timeout, .failure:
                state = .closed
                return .disconnect
            default:
                return .none
            }
        }

        switch event {
        case .failure, .cancel, .background, .timeout:
            lastDistance = nil
            if state == .preparing {
                state = .closed
                return .disconnect
            }
            // START may have reached the accessory even when its write ACK failed.
            state = .stopping
            return .writeStop
        default:
            break
        }

        switch state {
        case .preparing:
            switch event {
            case .authenticated: authenticated = true
            case .subscribed: subscribed = true
            case .configuration(let bytes):
                if !bytes.isEmpty { configuration = bytes }
            default: break
            }
            if authenticated, subscribed, configuration != nil {
                state = .starting
                return .writeStart
            }
        case .starting:
            if case .startAcknowledged = event, let configuration {
                state = .configuring
                return .writeConfiguration(configuration)
            }
        case .configuring:
            if case .configurationAcknowledged = event { state = .active }
        case .active, .stopping, .closed:
            break
        }
        return .none
    }

    /// Missing or invalid live measurements clear the previous display value.
    /// The caller must first match the object and the current NI session generation.
    @discardableResult
    public mutating func receiveDistance(_ distance: Double?) -> Double? {
        guard state == .active, let distance, distance.isFinite, distance >= 0 else {
            lastDistance = nil
            return nil
        }
        lastDistance = distance
        return distance
    }
}

/// Outgoing command counters are independent from encrypted incoming-read counters.
public struct UWBCommandCounter {
    public enum CounterError: Error { case exhausted }
    private var lastIssued: UInt32

    public init(lastIssued: UInt32 = 0) { self.lastIssued = lastIssued }

    public mutating func frame(payload: Data) throws -> Data {
        guard lastIssued < UInt32.max else { throw CounterError.exhausted }
        lastIssued += 1
        let value = lastIssued
        return Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ]) + payload
    }
}
