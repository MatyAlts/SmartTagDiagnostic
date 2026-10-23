import Foundation
import Combine
import NearbyInteraction
import SmartTagCore

/// Foreground-only trial. Only NI measurements for this session/token become distance.
@MainActor
final class NearbyInteractionClient: NSObject, ObservableObject, NISessionDelegate {
    @Published private(set) var distanceMeters: Double?
    @Published private(set) var phase = "Sin medición"
    @Published private(set) var errorMessage: String?
    @Published private(set) var events: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var attemptID: UUID?
    private let capabilityOverride: Bool?
    private var session: NISession?
    private var token: NIDiscoveryToken?
    private var accessoryAddress: UInt16 = 1
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var freshnessTimeout: Task<Void, Never>?
    private var sendConfiguration: ((Data) -> Void)?
    private var acceptDistance: ((Double?) -> Double?)?
    private var onStop: (() -> Void)?
    private var sentConfiguration = false
    private var progress = NITrialProgress()
    private var addressMode: SamsungUWBAddressMode = .baseline

    var supportsUWB: Bool {
        capabilityOverride ?? NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    init(capabilityOverride: Bool? = nil) {
        self.capabilityOverride = capabilityOverride
        super.init()
    }

    func start(version: AppleUWBVersion, addressMode: SamsungUWBAddressMode = .baseline,
               sendConfiguration: @escaping (Data) -> Void,
               acceptDistance: @escaping (Double?) -> Double?, onStop: @escaping () -> Void) {
        stop()
        errorMessage = nil
        self.sendConfiguration = sendConfiguration
        self.acceptDistance = acceptDistance
        self.onStop = onStop
        self.addressMode = addressMode
        guard supportsUWB else {
            fail("Este dispositivo no admite medición precisa UWB.")
            return
        }
        // Unit/UI tests never create an NI session or request hardware permissions.
        guard capabilityOverride == nil,
              !ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              NSClassFromString("XCTestCase") == nil else {
            fail("La sesión UWB está deshabilitada durante las pruebas automatizadas.")
            return
        }
        if version == .v2 {
            guard #available(iOS 26.1, *) else {
                fail("El perfil UWB 2.0 requiere iOS 26.1 o posterior.")
                return
            }
        }
        accessoryAddress = UInt16.random(in: 1...65533)
        let profile = UWBAccessoryProfile(version: version, accessoryAddress: accessoryAddress)
        do {
            let data = try AppleUWBProtocol.accessoryData(profile: profile)
            let configuration = try NINearbyAccessoryConfiguration(data: data)
            let next = NISession()
            session = next
            token = configuration.accessoryDiscoveryToken
            next.delegate = self
            next.delegateQueue = .main
            sentConfiguration = false
            isRunning = true
            attemptID = generation
            progress.begin(attemptID: generation, now: ProcessInfo.processInfo.systemUptime)
            phase = "Preparando Nearby Interaction…"
            events.append("Se solicitó una sesión NI con perfil experimental \(version == .v2 ? "2.0" : "1.1").")
            events.append("Ensayo de representación de direcciones: \(Self.addressModeDescription(addressMode)). No es una corrección de compatibilidad confirmada.")
            events.append("Declaraciones experimentales: fabricante, modelo y middleware en 0; deriva máxima 20 ppm. Capacidades no confirmadas para la etiqueta.")
            armProgressDeadline()
            next.run(configuration)
        } catch {
            fail("Nearby Interaction rechazó la configuración experimental (código \((error as NSError).code)).")
        }
    }

    func stop() {
        if isRunning {
            events.append("Resumen NI: \(progress.updateCount) actualizaciones del intento; etapa \(progress.stage.label).")
            if !progress.hasObservedRunning {
                events.append("Callback sessionDidStartRunning no observado para este intento; su ausencia no demuestra que la radio no iniciara.")
            }
        }
        generation = UUID()
        attemptID = nil; progress.stop()
        timeout?.cancel(); timeout = nil
        freshnessTimeout?.cancel(); freshnessTimeout = nil
        let old = session
        session = nil; token = nil
        old?.delegate = nil
        old?.invalidate()
        distanceMeters = nil
        isRunning = false
        sentConfiguration = false
        sendConfiguration = nil
        acceptDistance = nil
        let cleanup = onStop
        onStop = nil
        phase = "Sin medición"
        cleanup?()
    }

    func clear() {
        stop()
        errorMessage = nil
        events.removeAll()
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
        phase = "Prueba detenida"
        events.append(message)
    }

    private func armProgressDeadline() {
        timeout?.cancel(); timeout = nil
        guard let current = attemptID, let deadline = progress.deadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let nanoseconds = UInt64(max(1, ceil(delay * 1_000_000_000)))
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard let self, self.isRunning, self.attemptID == current else { return }
            if let expiry = self.progress.expiry(attemptID: current, now: ProcessInfo.processInfo.systemUptime) {
                self.fail(expiry.message)
            } else {
                self.armProgressDeadline()
            }
        }
    }

    private func expireIfNeeded(now: TimeInterval) -> Bool {
        guard let current = attemptID, let expiry = progress.expiry(attemptID: current, now: now) else { return false }
        fail(expiry.message)
        return true
    }

    @discardableResult
    func configurationAcknowledged(attemptID: UUID) -> Bool {
        guard isRunning, self.attemptID == attemptID, session != nil, token != nil, sentConfiguration else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        guard !expireIfNeeded(now: now), progress.transportAcknowledged(attemptID: attemptID, now: now) else { return false }
        events.append("La escritura de configuración recibió confirmación Bluetooth; comienza el plazo de medición de la app (30 s). No confirma éxito de radio.")
        phase = "Esperando medición UWB…"
        armProgressDeadline()
        return true
    }

    func sessionDidStartRunning(_ session: NISession) {
        guard self.session === session, isRunning, let current = attemptID,
              progress.observedRunning(attemptID: current) else { return }
        events.append("Se observó sessionDidStartRunning para este intento. Todavía no demuestra una medición de distancia.")
    }

    func session(_ session: NISession, didGenerateShareableConfigurationData data: Data,
                 for object: NINearbyObject) {
        guard self.session === session, isRunning, object.discoveryToken == token,
              !sentConfiguration else { return }
        guard let current = attemptID, !expireIfNeeded(now: ProcessInfo.processInfo.systemUptime) else { return }
        events.append(contentsOf: UWBDiagnostics.shareableSummary(data))
        let parameters: AppleUWBParameters
        do {
            parameters = try AppleUWBProtocol.decodeShareable(data)
        } catch {
            fail(UWBDiagnostics.rejection(error, stage: .appleDecode))
            return
        }
        do {
            let translated = try SamsungUWBProtocol.configuration(parameters: parameters, accessoryAddress: accessoryAddress,
                                                                  addressMode: addressMode)
            guard !expireIfNeeded(now: ProcessInfo.processInfo.systemUptime),
                  progress.configurationGenerated(attemptID: current) else { return }
            sentConfiguration = true
            phase = "Esperando confirmación Bluetooth…"
            events.append("Parámetros NI entregados al transporte Bluetooth; todavía no confirma recepción ni compatibilidad de radio.")
            sendConfiguration?(translated)
        } catch {
            let fields = UWBDiagnostics.unsupportedSamsungFields(parameters, accessoryAddress: accessoryAddress)
            if !fields.isEmpty { events.append("Campos fuera del perfil Samsung: " + fields.joined(separator: ", ") + ".") }
            fail(UWBDiagnostics.rejection(error, stage: .samsungTranslation))
        }
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard self.session === session, isRunning, let current = attemptID else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !expireIfNeeded(now: now) else { return }
        let object = nearbyObjects.first(where: { $0.discoveryToken == token })
        let raw = object.flatMap { $0.distance }.map(Double.init)
        let measured = raw.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let windowOpen = progress.acceptsMeasurements(attemptID: current, now: now)
        if progress.observeUpdate(attemptID: current) {
            events.append("Actualización NI #\(progress.updateCount): objeto esperado \(object == nil ? "ausente" : "presente"), distancia válida \(measured == nil ? "ausente" : "presente"); etapa \(progress.stage.label), confirmación de transporte \(windowOpen ? "recibida" : "pendiente").")
        }
        guard object != nil, sentConfiguration, windowOpen else {
            _ = acceptDistance?(nil)
            distanceMeters = nil
            phase = windowOpen ? "Sin medición" : "Esperando confirmación Bluetooth…"
            return
        }
        let accepted = acceptDistance?(measured)
        distanceMeters = progress.receiveMeasurement(acceptedDistance: accepted, attemptID: current, now: now)
        phase = distanceMeters == nil ? "Sin medición" : "Distancia UWB recibida"
        freshnessTimeout?.cancel(); freshnessTimeout = nil
        if distanceMeters != nil {
            timeout?.cancel(); timeout = nil
            let current = generation
            freshnessTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                _ = self.acceptDistance?(nil)
                self.distanceMeters = nil
                self.phase = "Sin medición reciente"
            }
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                 reason: NINearbyObject.RemovalReason) {
        guard self.session === session, nearbyObjects.contains(where: { $0.discoveryToken == token }) else { return }
        fail(Self.removalDescription(reason) + " Etapa: " + Self.transportPhase(sentConfiguration) + ". Volvé a iniciar la prueba.")
    }

    func sessionWasSuspended(_ session: NISession) {
        guard self.session === session else { return }
        fail("La sesión UWB fue suspendida. Mantené la app abierta y volvé a iniciar.")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard self.session === session else { return }
        fail(Self.invalidationDescription(error, configurationSent: sentConfiguration))
    }

    static func removalDescription(_ reason: NINearbyObject.RemovalReason) -> String {
        switch reason {
        case .timeout: return "Nearby Interaction retiró la etiqueta: timeout (se agotó el tiempo de la sesión)."
        case .peerEnded: return "Nearby Interaction retiró la etiqueta: peerEnded (el extremo remoto terminó la sesión)."
        @unknown default: return "Nearby Interaction retiró la etiqueta: motivo no reconocido."
        }
    }

    static func addressModeDescription(_ mode: SamsungUWBAddressMode) -> String {
        switch mode {
        case .baseline: return "Base (sin invertir)"
        case .accessoryLittleEndian: return "Solo etiqueta invertida"
        case .phoneLittleEndian: return "Solo iPhone invertido"
        case .bothLittleEndian: return "Ambas invertidas"
        }
    }

    static func invalidationDescription(_ error: Error, configurationSent: Bool) -> String {
        "Nearby Interaction invalidó la sesión (código \((error as NSError).code)). Etapa: \(transportPhase(configurationSent)). Revisá el permiso y volvé a iniciar."
    }

    private static func transportPhase(_ sent: Bool) -> String {
        sent ? "después del envío al transporte" : "antes del envío al transporte"
    }
}
