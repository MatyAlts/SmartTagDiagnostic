import Foundation

/// Uses the caller's monotonic clock; callbacks cannot revive an expired attempt.
struct NITrialProgress {
    enum Stage: Equatable {
        case idle, setup, awaitingTransport, ranging, measured, stopped
        var label: String {
            switch self {
            case .idle: return "sin intento"
            case .setup: return "preparación NI"
            case .awaitingTransport: return "espera de confirmación Bluetooth"
            case .ranging: return "espera de medición"
            case .measured: return "medición recibida"
            case .stopped: return "detenida"
            }
        }
    }

    enum Expiry: Equatable {
        case setup, ranging
        var message: String {
            switch self {
            case .setup:
                return "Se agotó el plazo de preparación de la app (30 s) antes de confirmar los parámetros por Bluetooth. Volvé a iniciar la prueba."
            case .ranging:
                return "Se agotó el plazo de medición de la app (30 s desde la confirmación Bluetooth) sin una distancia válida. Volvé a iniciar la prueba."
            }
        }
    }

    private(set) var stage: Stage = .idle
    private(set) var deadline: TimeInterval?
    private(set) var updateCount = 0
    private(set) var hasObservedRunning = false
    private var attemptID: UUID?

    mutating func begin(attemptID: UUID, now: TimeInterval) {
        self.attemptID = attemptID; stage = .setup; deadline = now + 30
        updateCount = 0; hasObservedRunning = false
    }

    mutating func configurationGenerated(attemptID: UUID) -> Bool {
        guard self.attemptID == attemptID, stage == .setup else { return false }
        stage = .awaitingTransport
        return true
    }

    mutating func transportAcknowledged(attemptID: UUID, now: TimeInterval) -> Bool {
        guard self.attemptID == attemptID, stage == .awaitingTransport,
              let deadline, now < deadline else { return false }
        stage = .ranging; self.deadline = now + 30
        return true
    }

    func expiry(attemptID: UUID, now: TimeInterval) -> Expiry? {
        guard self.attemptID == attemptID, let deadline, now >= deadline else { return nil }
        return stage == .ranging ? .ranging : .setup
    }

    func acceptsMeasurements(attemptID: UUID, now: TimeInterval) -> Bool {
        guard self.attemptID == attemptID else { return false }
        if stage == .measured { return true }
        return stage == .ranging && deadline.map { now < $0 } == true
    }

    mutating func receiveMeasurement(acceptedDistance: Double?, attemptID: UUID, now: TimeInterval) -> Double? {
        guard acceptsMeasurements(attemptID: attemptID, now: now),
              let acceptedDistance, acceptedDistance.isFinite, acceptedDistance >= 0 else { return nil }
        stage = .measured; deadline = nil
        return acceptedDistance
    }

    mutating func observedRunning(attemptID: UUID) -> Bool {
        guard self.attemptID == attemptID, !hasObservedRunning else { return false }
        hasObservedRunning = true
        return true
    }

    mutating func observeUpdate(attemptID: UUID) -> Bool {
        guard self.attemptID == attemptID else { return false }
        if updateCount < Int.max { updateCount += 1 }
        return updateCount <= 3
    }

    mutating func stop() {
        attemptID = nil; deadline = nil; stage = .stopped
    }
}
