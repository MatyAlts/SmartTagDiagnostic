/// The driver validates bytes before reporting a nonce or verified proof.
/// This reducer owns ordering and emits each wire action at most once.
public struct AuthenticationProgress {
    public enum Event: Hashable { case nonceWritten, tagNonce, proofWritten, proofVerified }
    public enum Action: Equatable { case wait, sendProof, readBattery }
    private var received: Set<Event> = []
    private var proofStarted = false
    private var completed = false
    private var stopped = false
    public init() {}
    public mutating func cancel() { stopped = true }
    public mutating func receive(_ event: Event) throws -> Action {
        guard !stopped, !completed, !received.contains(event),
              proofStarted || (event != .proofWritten && event != .proofVerified) else {
            stopped = true
            throw TagProtocolError.incorrectProof
        }
        received.insert(event)
        if !proofStarted, received.contains(.nonceWritten), received.contains(.tagNonce) {
            proofStarted = true
            return .sendProof
        }
        if proofStarted, received.contains(.proofWritten), received.contains(.proofVerified) {
            completed = true
            return .readBattery
        }
        return .wait
    }
}
