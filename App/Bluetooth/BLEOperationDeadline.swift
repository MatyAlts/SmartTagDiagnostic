import Foundation

/// A suspended task needs both its original arm and connection to remain current.
/// Cancellation alone cannot revoke a task that has already resumed on MainActor.
struct BLEOperationDeadline {
    enum Scope: Equatable {
        case scan, operation, rangingFallback, stopQueue, stopAcknowledgement, disconnect

        var duration: TimeInterval {
            switch self {
            case .scan: return 12
            case .operation: return 15
            case .rangingFallback: return 35
            case .stopQueue, .stopAcknowledgement: return 3
            case .disconnect: return 5
            }
        }
    }

    struct Ticket: Equatable {
        fileprivate let id = UUID()
        let scope: Scope
        let generation: UInt64?
        let deadline: TimeInterval
    }

    private(set) var current: Ticket?

    mutating func arm(_ scope: Scope, generation: UInt64?, now: TimeInterval) -> Ticket {
        let ticket = Ticket(scope: scope, generation: generation, deadline: now + scope.duration)
        current = ticket
        return ticket
    }

    mutating func cancel() { current = nil }

    mutating func consume(_ ticket: Ticket, generation: UInt64?, now: TimeInterval) -> Scope? {
        guard current == ticket, ticket.generation == generation, now >= ticket.deadline else { return nil }
        current = nil
        return ticket.scope
    }
}
