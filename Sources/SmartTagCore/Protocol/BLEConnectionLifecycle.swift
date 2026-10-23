/// A cancellation request keeps ownership until the transport closes or is retired.
/// Peripheral delegates retain the returned generation for callback validation.
public struct BLEConnectionLifecycle {
    public enum State: Equatable { case idle, connecting, connected, disconnecting }
    public private(set) var state: State = .idle
    public private(set) var currentGeneration: UInt64?
    private var lastGeneration: UInt64 = 0

    public init() {}

    public mutating func beginConnection() -> UInt64? {
        guard state == .idle, lastGeneration < UInt64.max else { return nil }
        lastGeneration += 1
        currentGeneration = lastGeneration
        state = .connecting
        return currentGeneration
    }

    public mutating func didConnect(generation: UInt64) -> Bool {
        guard currentGeneration == generation, state == .connecting else { return false }
        state = .connected
        return true
    }

    public mutating func beginDisconnect(generation: UInt64) -> Bool {
        guard currentGeneration == generation, state == .connecting || state == .connected else { return false }
        state = .disconnecting
        return true
    }

    public mutating func didDisconnect(generation: UInt64) -> Bool {
        guard currentGeneration == generation, state != .idle else { return false }
        state = .idle
        currentGeneration = nil
        return true
    }

    public func acceptsCallback(generation: UInt64) -> Bool {
        currentGeneration == generation && (state == .connecting || state == .connected)
    }
}
