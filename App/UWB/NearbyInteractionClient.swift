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

    var supportsUWB: Bool {
        capabilityOverride ?? NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    init(capabilityOverride: Bool? = nil) {
        self.capabilityOverride = capabilityOverride
        super.init()
    }

    func start(version: AppleUWBVersion, sendConfiguration: @escaping (Data) -> Void,
               acceptDistance: @escaping (Double?) -> Double?, onStop: @escaping () -> Void) {
        stop()
        errorMessage = nil
        self.sendConfiguration = sendConfiguration
        self.acceptDistance = acceptDistance
        self.onStop = onStop
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
            phase = "Preparando Nearby Interaction…"
            events.append("Sesión NI iniciada con perfil experimental \(version == .v2 ? "2.0" : "1.1").")
            events.append("Declaraciones experimentales: fabricante, modelo y middleware en 0; deriva máxima 20 ppm. Capacidades no confirmadas para la etiqueta.")
            let current = generation
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self, self.generation == current else { return }
                self.fail("La prueba UWB terminó sin establecer mediciones. Volvé a iniciar para reintentar.")
            }
            next.run(configuration)
        } catch {
            fail("Nearby Interaction rechazó la configuración experimental (código \((error as NSError).code)).")
        }
    }

    func stop() {
        generation = UUID()
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

    func session(_ session: NISession, didGenerateShareableConfigurationData data: Data,
                 for object: NINearbyObject) {
        guard self.session === session, isRunning, object.discoveryToken == token,
              !sentConfiguration else { return }
        let bytes = [UInt8](data)
        var structure = "Configuración NI: \(bytes.count) bytes"
        if bytes.count >= 4 {
            let major = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
            let minor = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
            structure += ", versión \(major).\(minor)"
        }
        events.append(structure + ".")
        do {
            let parameters = try AppleUWBProtocol.decodeShareable(data)
            events.append("Perfil NI: canal \(parameters.channel), preámbulo \(parameters.preamble), slots \(parameters.slots), duración \(parameters.slotDurationRSTU) RSTU, intervalo \(parameters.intervalMilliseconds) ms, control \(parameters.roundControl), hopping \(parameters.hopping).")
            let translated = try SamsungUWBProtocol.configuration(parameters: parameters, accessoryAddress: accessoryAddress)
            sentConfiguration = true
            phase = "Esperando medición UWB…"
            sendConfiguration?(translated)
        } catch {
            fail("La configuración generada por Nearby Interaction no coincide con el perfil experimental. Consultá el registro técnico.")
        }
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard self.session === session, isRunning, sentConfiguration else { return }
        guard let object = nearbyObjects.first(where: { $0.discoveryToken == token }) else {
            _ = acceptDistance?(nil)
            distanceMeters = nil
            phase = "Sin medición"
            return
        }
        let raw = object.distance.map(Double.init)
        let measured = raw.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let accepted = acceptDistance?(measured)
        distanceMeters = accepted.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
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
        fail("Nearby Interaction perdió la etiqueta. Volvé a iniciar la prueba.")
    }

    func sessionWasSuspended(_ session: NISession) {
        guard self.session === session else { return }
        fail("La sesión UWB fue suspendida. Mantené la app abierta y volvé a iniciar.")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard self.session === session else { return }
        fail("Nearby Interaction detuvo la sesión (código \((error as NSError).code)). Revisá el permiso y volvé a iniciar.")
    }
}
