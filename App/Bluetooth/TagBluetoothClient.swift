import Foundation
import Combine
import CoreBluetooth
import Security
import SmartTagCore

struct NearbyTag: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
}

/// Battery-only remains the default; UWB and ringing require separate explicit connections.
@MainActor final class TagBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var candidates: [NearbyTag] = []
    @Published private(set) var phase = "En espera"
    @Published private(set) var isBusy = false
    @Published private(set) var battery: BatteryLevel?
    @Published private(set) var errorMessage: String?
    @Published private(set) var events: [String] = []
    @Published private(set) var uwbReady = false
    @Published private(set) var uwbActive = false
    @Published private(set) var ringStatus = "Sin prueba de sonido"
    @Published private(set) var ringCanStop = false

    private static let encryption = CBUUID(string: "EEDD5E73-6AA8-4673-8219-398A489DA87C")
    private static let nonce = CBUUID(string: "A12BE31C-5B38-4773-9B9D-3D5735233A7C")
    private static let proof = CBUUID(string: "4EBE81F6-B952-465E-9ECE-5CA39D4E8955")
    private static let service = CBUUID(string: "FD5A")
    private static let ringID = CBUUID(string: RingNotificationInspector.characteristic)
    private static let batteryID = CBUUID(string: "DEE30004-182D-5496-B1AD-14F216324184")
    private static let uwbControl = CBUUID(string: "DEE30008-182D-5496-B1AD-14F216324184")
    private static let uwbParameters = CBUUID(string: "DEE30009-182D-5496-B1AD-14F216324184")
    private var central: CBCentralManager?
    private var pendingScan = false
    private var found: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var credentials: TagCredentials?
    private var phoneNonce = Data()
    private var tagNonce: Data?
    private var authentication = AuthenticationProgress()
    private var proofVerified = false
    private var batteryRequested = false
    private var timeout: Task<Void, Never>?
    private var operationDeadline = BLEOperationDeadline()
    private let timeline: DiagnosticTimeline
    private var replay = ReplayCounter()
    private enum ConnectionPurpose { case battery, uwb, ring }
    private var purpose: ConnectionPurpose = .battery
    private var forUWB: Bool { purpose == .uwb }
    private var forRing: Bool { purpose == .ring }
    private var ringProgress = RingTrialProgress()
    private var ringTrialID: UUID?
    private enum RingWrite { case start, stop }
    private var pendingRingWrite: RingWrite?
    private var ringAutoStop: Task<Void, Never>?
    private var subscriptionsStarted = false
    private var uwbFlow = UWBExperimentFlow()
    private var commandCounter = UWBCommandCounter()
    private enum UWBWrite: Equatable { case start, configuration, stop }
    private var pendingUWBWrite: UWBWrite?
    private var expectedUWBConfiguration: Data?
    private var queuedStop = false
    private var connectionLifecycle = BLEConnectionLifecycle()
    private var attemptDelegate: BLEAttemptDelegate?

    init(timeline: DiagnosticTimeline = .process) {
        self.timeline = timeline
        super.init()
    }

    func scan() {
        guard !isBusy else { return }
        if central == nil {
            clear(); pendingScan = true; isBusy = true; phase = "Preparando Bluetooth"
            central = CBCentralManager(delegate: self, queue: .main)
            armTimeout()
            return
        }
        guard let central else { return }
        if central.state == .unknown || central.state == .resetting {
            pendingScan = true; isBusy = true; phase = "Preparando Bluetooth"; armTimeout()
            return
        }
        guard central.state == .poweredOn else {
            fail("Activá Bluetooth y permití su acceso desde Ajustes."); return
        }
        clear(); candidates = []; found = [:]
        isBusy = true; phase = "Buscando etiquetas cercanas"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        armTimeout(.scan)
        log("Búsqueda iniciada. Seleccioná tu etiqueta; la autenticación comprobará su identidad.")
    }

    func connect(candidateID: UUID, credentials: TagCredentials, forUWB: Bool = false) {
        connect(candidateID: candidateID, credentials: credentials, purpose: forUWB ? .uwb : .battery)
    }

    func startRing(candidateID: UUID, credentials: TagCredentials) {
        connect(candidateID: candidateID, credentials: credentials, purpose: .ring)
    }

    private func connect(candidateID: UUID, credentials: TagCredentials, purpose: ConnectionPurpose) {
        guard connectionLifecycle.state == .idle else {
            log("La conexión anterior todavía se está cerrando; esperá antes de reintentar.")
            return
        }
        guard peripheral == nil, let candidate = found[candidateID], let central, central.state == .poweredOn else {
            fail("Seleccioná una etiqueta detectada con Bluetooth disponible."); return
        }
        central.stopScan(); cancelTimeout()
        resetHandshake(); self.purpose = purpose
        self.credentials = credentials; battery = nil; errorMessage = nil
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            fail("No se pudieron generar datos aleatorios seguros."); return
        }
        guard let generation = connectionLifecycle.beginConnection() else { return }
        if forRing {
            let trial = UUID(); ringTrialID = trial
            ringProgress.begin(generation: generation, trialID: trial)
            ringCanStop = true; ringStatus = "Preparando sonido autenticado…"
        }
        phoneNonce = Data(random); peripheral = candidate
        let delegate = BLEAttemptDelegate(owner: self, generation: generation)
        attemptDelegate = delegate; candidate.delegate = delegate
        isBusy = true; phase = "Conectando"; central.connect(candidate)
        armTimeout(); log("Conectando con el dispositivo seleccionado.")
    }

    func disconnect() {
        if forRing { stopRing() }
        else if forUWB { stopUWB() }
        else { finishDisconnect() }
    }

    private func finishDisconnect() {
        expectedUWBConfiguration = nil
        if connectionLifecycle.state == .disconnecting { return }
        pendingScan = false; central?.stopScan(); cancelTimeout()
        guard let peripheral, let generation = connectionLifecycle.currentGeneration else {
            credentials = nil; resetHandshake(); authentication.cancel()
            isBusy = false; phase = "Desconectado"; return
        }
        guard connectionLifecycle.beginDisconnect(generation: generation) else { return }
        // Keep the peripheral and cancellation barrier, but wipe session secrets now.
        credentials = nil; resetHandshake(); authentication.cancel()
        isBusy = true; phase = "Cerrando la conexión Bluetooth"
        log("Se solicitó el cierre Bluetooth; plazo de confirmación 5 s.")
        central?.cancelPeripheralConnection(peripheral)
        armTimeout(.disconnect)
    }

    private func completeDisconnect(generation: UInt64, retiredManager: Bool = false) {
        guard connectionLifecycle.currentGeneration == generation else { return }
        if forRing, ringProgress.phase != .closed {
            if let trial = ringTrialID { ringProgress.connectionLost(generation: generation, trialID: trial) }
            ringStatus = "Conexión perdida; no se confirmó que el sonido se haya detenido."
            log(ringStatus)
        }
        guard connectionLifecycle.didDisconnect(generation: generation) else { return }
        cancelTimeout(); peripheral?.delegate = nil; attemptDelegate = nil
        peripheral = nil; credentials = nil; resetHandshake(); authentication.cancel()
        isBusy = false
        phase = errorMessage == nil ? "Conexión cerrada; podés volver a intentar" : "Detenido"
        if !retiredManager {
            log("CoreBluetooth confirmó el cierre. La selección cercana se conserva para reintentar.")
        }
    }

    fileprivate func acceptsPeripheralCallback(_ peripheral: CBPeripheral, generation: UInt64) -> Bool {
        self.peripheral === peripheral && connectionLifecycle.acceptsCallback(generation: generation)
    }

    func clear() {
        disconnect(); errorMessage = nil; battery = nil; events = []; phase = "En espera"
        if !isBusy { ringStatus = "Sin prueba de sonido" }
    }

    private func resetHandshake() {
        expectedUWBConfiguration = nil
        phoneNonce = Data(); tagNonce = nil; characteristics = [:]
        authentication = AuthenticationProgress()
        proofVerified = false; batteryRequested = false; replay = ReplayCounter()
        subscriptionsStarted = false; purpose = .battery
        ringAutoStop?.cancel(); ringAutoStop = nil
        ringProgress = RingTrialProgress(); ringTrialID = nil; pendingRingWrite = nil; ringCanStop = false
        uwbReady = false; uwbActive = false; uwbFlow = UWBExperimentFlow()
        commandCounter = UWBCommandCounter(); pendingUWBWrite = nil; queuedStop = false
    }
    private func log(_ message: String) {
        events.append(timeline.stamp(message))
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
    private func fail(_ message: String) {
        expectedUWBConfiguration = nil
        errorMessage = message; log(message)
        if forRing {
            if connectionLifecycle.currentGeneration != nil, ringTrialID != nil { stopRing() }
            else { finishDisconnect() }
        } else if forUWB { performUWB(uwbFlow.receive(.failure)) }
        else { finishDisconnect() }
        phase = "Detenido"
    }
    private func cancelTimeout() {
        timeout?.cancel(); timeout = nil
        operationDeadline.cancel()
    }

    private func armTimeout(_ scope: BLEOperationDeadline.Scope = .operation) {
        // Late discovery/auth callbacks cannot replace an in-flight STOP budget.
        guard scope != .operation || (uwbFlow.state != .stopping && ringProgress.phase != .stopping) else { return }
        cancelTimeout()
        let ticket = operationDeadline.arm(scope, generation: connectionLifecycle.currentGeneration,
                                           now: ProcessInfo.processInfo.systemUptime)
        timeout = Task { [weak self] in
            // Recheck the monotonic boundary after sleep; an early wake must not
            // discard the current deadline or act on a newer operation.
            while !Task.isCancelled {
                let delay = max(0, ticket.deadline - ProcessInfo.processInfo.systemUptime)
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(ceil(delay * 1_000_000_000))) }
                    catch { return }
                }
                guard !Task.isCancelled, let self,
                      self.operationDeadline.current == ticket else { return }
                guard let expired = self.operationDeadline.consume(ticket,
                    generation: self.connectionLifecycle.currentGeneration,
                    now: ProcessInfo.processInfo.systemUptime) else {
                    if ticket.generation != self.connectionLifecycle.currentGeneration { return }
                    continue
                }
                self.timeout = nil
                self.deadlineExpired(expired, generation: ticket.generation)
                return
            }
        }
    }

    private func deadlineExpired(_ scope: BLEOperationDeadline.Scope, generation: UInt64?) {
        switch scope {
        case .scan:
            central?.stopScan(); isBusy = false; phase = "Seleccioná una etiqueta cercana"
            log("Búsqueda finalizada.")
        case .operation:
            fail("Se agotó el tiempo de la operación Bluetooth.")
        case .rangingFallback:
            fail("Venció el límite de seguridad Bluetooth (35 s desde la configuración); se solicita detener UWB.")
        case .stopQueue:
            if forRing { finishUnconfirmedRingStop(); return }
            log("Venció la espera de la escritura pendiente (3 s); STOP no llegó a enviarse. Se solicita cerrar Bluetooth.")
            performUWB(uwbFlow.receive(.timeout))
        case .stopAcknowledgement:
            if forRing { finishUnconfirmedRingStop(); return }
            log("Venció el plazo de confirmación de STOP (3 s desde su envío); se solicita cerrar Bluetooth.")
            performUWB(uwbFlow.receive(.timeout))
        case .disconnect:
            guard let generation, connectionLifecycle.state == .disconnecting else { return }
            // Retire the manager so late central callbacks cannot reach a retry.
            central?.delegate = nil; central = nil
            found = [:]; candidates = []
            completeDisconnect(generation: generation, retiredManager: true)
            errorMessage = "Bluetooth no confirmó el cierre. Volvé a buscar dispositivos cercanos."
            phase = "Se reinició la conexión Bluetooth"
            log("Se retiró la conexión anterior por falta de confirmación de cierre; hace falta una nueva búsqueda.")
        }
    }

    private func beginSubscriptionsIfReady() {
        guard !subscriptionsStarted, let peripheral, let nonce = characteristics[Self.nonce],
              let proof = characteristics[Self.proof], characteristics[Self.batteryID] != nil else { return }
        if forRing {
            guard let ring = characteristics[Self.ringID], ring.properties.contains(.write),
                  ring.properties.contains(.notify) || ring.properties.contains(.indicate) else {
                fail("La etiqueta no ofrece las operaciones de sonido necesarias."); return
            }
        }
        if forUWB {
            guard let control = characteristics[Self.uwbControl],
                  let parameters = characteristics[Self.uwbParameters] else { return }
            guard control.properties.contains(.write), parameters.properties.contains(.write),
                  parameters.properties.contains(.notify) || parameters.properties.contains(.indicate) else {
                fail("La etiqueta no ofrece las operaciones GATT de la prueba UWB."); return
            }
        }
        guard nonce.properties.contains(.write), proof.properties.contains(.write),
              nonce.properties.contains(.notify) || nonce.properties.contains(.indicate),
              proof.properties.contains(.notify) || proof.properties.contains(.indicate),
              characteristics[Self.batteryID]!.properties.contains(.read) else {
            fail("Las operaciones GATT necesarias no están disponibles."); return
        }
        subscriptionsStarted = true
        phase = "Preparando las notificaciones de autenticación"; peripheral.setNotifyValue(true, for: nonce); armTimeout()
    }

    private func advanceAuthentication(_ event: AuthenticationProgress.Event) {
        guard let peripheral, let credentials, uwbFlow.state != .stopping else { return }
        do {
            let key = SmartTagCrypto.derive(master: credentials.masterSecret, context: Data("bleAuthentication".utf8))
            switch try authentication.receive(event) {
            case .sendProof:
                guard let tagNonce, let proof = characteristics[Self.proof] else { throw TagProtocolError.incorrectProof }
                let encrypted = try SmartTagCrypto.encrypt(Data("smartthings".utf8), key: key, iv: tagNonce)
                phase = "Verificando la etiqueta"; peripheral.writeValue(encrypted, for: proof, type: .withResponse); armTimeout()
            case .readBattery:
                guard proofVerified, !batteryRequested, let battery = characteristics[Self.batteryID] else {
                    throw TagProtocolError.incorrectProof
                }
                batteryRequested = true; phase = "Leyendo la batería"; peripheral.readValue(for: battery); armTimeout()
            case .wait: break
            }
        } catch { fail("Falló la validación criptográfica de autenticación.") }
    }

    func sendUWBConfiguration(_ configuration: Data) {
        guard forUWB, uwbReady, proofVerified, battery != nil,
              peripheral?.state == .connected, configuration.count == 35,
              uwbFlow.state == .preparing else {
            fail("La prueba UWB requiere una conexión autenticada y una configuración válida."); return
        }
        performUWB(uwbFlow.receive(.configuration(configuration)))
    }

    func stopUWB() {
        guard !forRing else { return }
        expectedUWBConfiguration = nil
        uwbReady = false; uwbActive = false
        guard forUWB else { finishDisconnect(); return }
        performUWB(uwbFlow.receive(.cancel))
    }

    func acceptUWBDistance(_ distance: Double?) -> Double? {
        guard forUWB, proofVerified, peripheral?.state == .connected else { return nil }
        return uwbFlow.receiveDistance(distance)
    }

    private func performUWB(_ action: UWBExperimentFlow.Action) {
        switch action {
        case .none: break
        case .writeStart:
            // Readiness represents the retained authenticated session lifetime.
            // The flow state prevents a second configuration while NI is running.
            phase = "Activando UWB en la etiqueta"
            writeUWB(.start, payload: Data([1]), characteristic: Self.uwbControl)
        case .writeConfiguration(let data):
            phase = "Enviando parámetros UWB"
            writeUWB(.configuration, payload: data, characteristic: Self.uwbParameters)
        case .writeStop:
            expectedUWBConfiguration = nil
            uwbReady = false; uwbActive = false; queuedStop = true
            phase = "Deteniendo UWB"
            log("Se solicitó detener UWB.")
            if pendingUWBWrite != nil {
                log("STOP espera una escritura anterior; plazo de espera 3 s.")
                armTimeout(.stopQueue)
            }
            flushUWBStop()
        case .disconnect:
            finishDisconnect()
        }
    }

    private func flushUWBStop() {
        // START and STOP share a UUID: never mistake a late START ACK for STOP.
        guard queuedStop, pendingUWBWrite == nil else { return }
        queuedStop = false
        writeUWB(.stop, payload: Data([0]), characteristic: Self.uwbControl)
    }

    private func writeUWB(_ kind: UWBWrite, payload: Data, characteristic id: CBUUID) {
        guard pendingUWBWrite == nil, let peripheral, peripheral.state == .connected,
              central?.state == .poweredOn, proofVerified, let credentials, let tagNonce,
              let characteristic = characteristics[id], characteristic.properties.contains(.write) else {
            if uwbFlow.state == .stopping {
                log("STOP no se pudo enviar con la conexión actual; se solicita cerrar Bluetooth.")
                finishDisconnect()
            } else { fail("No se puede enviar la orden UWB con esta conexión.") }
            return
        }
        do {
            let key = SmartTagCrypto.derive(master: credentials.masterSecret, context: tagNonce)
            let frame = try commandCounter.frame(payload: payload)
            let encrypted = try SmartTagCrypto.encrypt(frame, key: key, iv: tagNonce)
            guard encrypted.count <= peripheral.maximumWriteValueLength(for: .withResponse) else {
                throw TagProtocolError.invalidLength
            }
            pendingUWBWrite = kind
            if kind == .configuration {
                expectedUWBConfiguration = payload.count == 35 ? payload : nil
            }
            if kind == .stop { log("STOP entregado a CoreBluetooth; plazo de confirmación 3 s.") }
            peripheral.writeValue(encrypted, for: characteristic, type: .withResponse)
            armTimeout(kind == .stop ? .stopAcknowledgement : .operation)
        } catch {
            if uwbFlow.state == .stopping {
                log("No se pudo preparar STOP; se solicita cerrar Bluetooth.")
                finishDisconnect()
            } else { fail("No se pudo preparar la orden cifrada UWB.") }
        }
    }

    private func didWriteUWB(_ characteristic: CBCharacteristic, error: Error?) {
        guard let pending = pendingUWBWrite else { return }
        let expected = pending == .configuration ? Self.uwbParameters : Self.uwbControl
        guard characteristic.uuid == expected else { return }
        pendingUWBWrite = nil
        if uwbFlow.state == .stopping, pending != .stop {
            log("Terminó la escritura anterior; se intenta enviar STOP.")
            flushUWBStop(); return
        }
        guard error == nil else {
            fail("La etiqueta rechazó una escritura UWB."); return
        }
        switch pending {
        case .start:
            log("La escritura de activación UWB fue confirmada; todavía no hay distancia.")
            performUWB(uwbFlow.receive(.startAcknowledged))
        case .configuration:
            performUWB(uwbFlow.receive(.configurationAcknowledged))
            uwbActive = uwbFlow.state == .active
            phase = "Esperando una medición UWB real"
            log("Parámetros UWB enviados. La confirmación Bluetooth no demuestra compatibilidad de radio.")
            log("Límite de seguridad Bluetooth armado a 35 s; NI conserva su plazo de medición de 30 s.")
            armTimeout(.rangingFallback)
        case .stop:
            log("La escritura de parada UWB fue confirmada.")
            performUWB(uwbFlow.receive(.stopAcknowledged))
        }
    }
}

/// CoreBluetooth can reuse the same peripheral instance on the next connection.
/// Each delegate captures its attempt token rather than using object identity alone.
@MainActor private final class BLEAttemptDelegate: NSObject, CBPeripheralDelegate {
    private weak var owner: TagBluetoothClient?
    private let generation: UInt64

    init(owner: TagBluetoothClient, generation: UInt64) {
        self.owner = owner; self.generation = generation
    }

    private func currentOwner(_ peripheral: CBPeripheral) -> TagBluetoothClient? {
        guard let owner, owner.acceptsPeripheralCallback(peripheral, generation: generation) else { return nil }
        return owner
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        currentOwner(peripheral)?.peripheral(peripheral, didDiscoverServices: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        currentOwner(peripheral)?.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        currentOwner(peripheral)?.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        currentOwner(peripheral)?.peripheral(peripheral, didWriteValueFor: characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        currentOwner(peripheral)?.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
    }
}

extension TagBluetoothClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard self.central === central else { return }
        if pendingScan {
            if central.state == .unknown || central.state == .resetting { return }
            pendingScan = false; isBusy = false; cancelTimeout()
            if central.state == .poweredOn { scan() }
            else { fail("Activá Bluetooth y permití su acceso desde Ajustes.") }
            return
        }
        if central.state != .poweredOn, isBusy { fail("Bluetooth dejó de estar disponible.") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.central === central, self.peripheral == nil else { return }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let samsung = manufacturer.map { $0.count >= 2 && $0.prefix(2) == Data([0x75,0]) } ?? false
        guard services.contains(Self.service) || samsung else { return }
        guard (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue != false else { return }
        found[peripheral.identifier] = peripheral
        let rawName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Dispositivo Samsung cercano"
        let scalars = rawName.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(60)
        let name = String(String.UnicodeScalarView(scalars))
        let candidate = NearbyTag(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        candidates.removeAll { $0.id == candidate.id }; candidates.append(candidate)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.central === central, self.peripheral === peripheral,
              let generation = connectionLifecycle.currentGeneration else { return }
        guard connectionLifecycle.didConnect(generation: generation) else {
            if connectionLifecycle.state == .disconnecting { central.cancelPeripheralConnection(peripheral) }
            return
        }
        phase = "Buscando servicios"; peripheral.discoverServices([Self.encryption, Self.service]); armTimeout()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.central === central, self.peripheral === peripheral,
              let generation = connectionLifecycle.currentGeneration else { return }
        let closing = connectionLifecycle.state == .disconnecting
        if !closing { errorMessage = "No se pudo conectar con la etiqueta."; log("No se pudo conectar con la etiqueta.") }
        completeDisconnect(generation: generation)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.central === central, self.peripheral === peripheral,
              let generation = connectionLifecycle.currentGeneration else { return }
        let closing = connectionLifecycle.state == .disconnecting || uwbFlow.state == .stopping
        if !closing { errorMessage = "La etiqueta se desconectó."; log("La etiqueta se desconectó.") }
        completeDisconnect(generation: generation)
    }
}

extension TagBluetoothClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let services = peripheral.services,
              services.contains(where: { $0.uuid == Self.encryption }),
              services.contains(where: { $0.uuid == Self.service }) else { fail("No se encontraron los servicios de la etiqueta."); return }
        for service in services {
            let control = forRing ? [Self.batteryID, Self.ringID] :
                (forUWB ? [Self.batteryID, Self.uwbControl, Self.uwbParameters] : [Self.batteryID])
            peripheral.discoverCharacteristics(service.uuid == Self.encryption ? [Self.nonce, Self.proof] : control, for: service)
        }
        armTimeout()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let values = service.characteristics else { fail("Falló la búsqueda de características GATT."); return }
        for value in values { characteristics[value.uuid] = value }
        beginSubscriptionsIfReady()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard uwbFlow.state != .stopping else { return }
        if characteristic.uuid == Self.ringID {
            guard forRing, proofVerified, battery != nil, error == nil, characteristic.isNotifying,
                  let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID else {
                fail("No se pudieron preparar las notificaciones de sonido."); return
            }
            performRing(ringProgress.ready(generation: generation, trialID: trial))
            return
        }
        if characteristic.uuid == Self.uwbParameters {
            guard forUWB, proofVerified, error == nil, characteristic.isNotifying else {
                fail("Falló la suscripción a los mensajes UWB."); return
            }
            performUWB(uwbFlow.receive(.subscribed))
            uwbReady = true
            phase = "Conexión autenticada preparada para Nearby Interaction"
            log("La prueba UWB está preparada para recibir los parámetros del iPhone.")
            armTimeout(); return
        }
        guard error == nil, characteristic.isNotifying else { fail("Falló la suscripción a notificaciones de autenticación."); return }
        if characteristic.uuid == Self.nonce, let proof = characteristics[Self.proof] {
            peripheral.setNotifyValue(true, for: proof); armTimeout()
        } else if characteristic.uuid == Self.proof, let nonce = characteristics[Self.nonce] {
            phase = "Intercambiando valores de autenticación"; peripheral.writeValue(phoneNonce, for: nonce, type: .withResponse); armTimeout()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        if characteristic.uuid == Self.ringID { didWriteRing(error: error); return }
        if characteristic.uuid == Self.uwbControl || characteristic.uuid == Self.uwbParameters {
            didWriteUWB(characteristic, error: error); return
        }
        guard uwbFlow.state != .stopping else { return }
        guard error == nil else { fail("La etiqueta rechazó la escritura de autenticación."); return }
        if characteristic.uuid == Self.nonce { advanceAuthentication(.nonceWritten) }
        if characteristic.uuid == Self.proof { advanceAuthentication(.proofWritten) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard uwbFlow.state != .stopping else { return }
        if characteristic.uuid == Self.ringID { receiveRingStatus(characteristic, error: error); return }
        if characteristic.uuid == Self.uwbParameters {
            guard forUWB, proofVerified, peripheral.state == .connected,
                  let tagNonce, let credentials else { return }
            guard error == nil, let value = characteristic.value else {
                log("No se pudo leer la notificación UWB."); return
            }
            switch UWBNotificationInspector.inspect(ciphertext: value,
                master: credentials.masterSecret, tagNonce: tagNonce, replay: &replay,
                expectedConfiguration: expectedUWBConfiguration) {
            case .accepted(let payloadLength, let comparison):
                log("Notificación UWB descifrada: carga de \(payloadLength) bytes; contenido desconocido, sin medición de distancia.")
                switch comparison {
                case .matches: log("Comparación con el paquete enviado: coincide exactamente; no confirma éxito de radio.")
                case .different: log("Comparación con el paquete enviado: diferente; significado desconocido.")
                case .notAvailable: log("Comparación con el paquete enviado: no disponible.")
                }
            case .invalidCiphertext:
                log("Notificación UWB descartada: cifrado o relleno no válido.")
            case .invalidFrame:
                log("Notificación UWB descartada: trama descifrada incompleta.")
            case .replayRejected:
                log("Notificación UWB descartada: mensaje repetido o fuera de orden.")
            }
            return
        }
        guard error == nil, let value = characteristic.value, let credentials else { fail("Falló la lectura Bluetooth."); return }
        do {
            switch characteristic.uuid {
            case Self.nonce:
                guard value.count == 16, tagNonce == nil, value != phoneNonce else { throw TagProtocolError.invalidLength }
                tagNonce = value; advanceAuthentication(.tagNonce)
            case Self.proof:
                guard !proofVerified else { throw TagProtocolError.incorrectProof }
                let key = SmartTagCrypto.derive(master: credentials.masterSecret, context: Data("bleAuthentication".utf8))
                try SmartTagCrypto.verifyProof(value, key: key, phoneNonce: phoneNonce)
                proofVerified = true; advanceAuthentication(.proofVerified)
            case Self.batteryID:
                guard batteryRequested, proofVerified, let tagNonce else { throw TagProtocolError.incorrectProof }
                let key = SmartTagCrypto.derive(master: credentials.masterSecret, context: tagNonce)
                let frame = try SmartTagFrame.decode(SmartTagCrypto.decrypt(value, key: key, iv: tagNonce))
                try replay.accept(frame.counter)
                let level = try BatteryLevel.decode(frame.payload)
                if forRing, let ring = characteristics[Self.ringID] {
                    battery = level
                    log("Batería autenticada leída; se preparan las notificaciones de sonido.")
                    phase = "Preparando sonido"
                    peripheral.setNotifyValue(true, for: ring); armTimeout()
                } else if forUWB, let parameters = characteristics[Self.uwbParameters] {
                    battery = level
                    log("Se completó la lectura autenticada de batería; se conserva la conexión para la prueba UWB.")
                    performUWB(uwbFlow.receive(.authenticated))
                    phase = "Preparando las notificaciones UWB"
                    peripheral.setNotifyValue(true, for: parameters); armTimeout()
                } else {
                    disconnect(); battery = level; phase = "Lectura de batería completada"; log("Se completó la lectura autenticada de batería.")
                }
            default: break
            }
        } catch {
            fail((error as? TagProtocolError)?.errorDescription ?? "La respuesta cifrada de la etiqueta no es válida.")
        }
    }
}


extension TagBluetoothClient {
    func stopRing() {
        guard forRing, let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID else { return }
        performRing(ringProgress.requestStop(generation: generation, trialID: trial))
    }

    private func performRing(_ action: RingTrialProgress.Action) {
        switch action {
        case .none: break
        case .writeStart: writeRing(.start)
        case .waitForStart:
            ringAutoStop?.cancel(); ringAutoStop = nil
            ringStatus = "Parada solicitada; esperando la escritura de inicio…"
            log("Sonido: STOP espera la escritura START, hasta 3 s.")
            armTimeout(.stopQueue)
        case .writeStop:
            ringAutoStop?.cancel(); ringAutoStop = nil
            ringStatus = "Parada solicitada; esperando confirmación…"
            writeRing(.stop)
        case .close:
            ringAutoStop?.cancel(); ringAutoStop = nil; ringCanStop = false
            switch ringProgress.evidence {
            case .notificationStopped: ringStatus = "La etiqueta notificó sonido detenido."
            case .writeAcknowledged: ringStatus = "STOP confirmado por Bluetooth; sin confirmación de cese audible."
            case .unknown:
                ringStatus = ringProgress.hasDispatchedStart ? "No se confirmó que el sonido se haya detenido." : "Inicio de sonido no enviado."
            }
            log(ringStatus); finishDisconnect()
        }
    }

    private func writeRing(_ kind: RingWrite) {
        guard forRing, pendingRingWrite == nil, pendingUWBWrite == nil,
              let peripheral, peripheral.state == .connected, central?.state == .poweredOn,
              proofVerified, battery != nil, let credentials, let tagNonce,
              let characteristic = characteristics[Self.ringID], characteristic.properties.contains(.write),
              let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID else {
            finishUnconfirmedRingStop(); return
        }
        do {
            let payload = kind == .start ? RingNotificationInspector.startPayload : RingNotificationInspector.stopPayload
            let key = SmartTagCrypto.derive(master: credentials.masterSecret, context: tagNonce)
            let encrypted = try SmartTagCrypto.encrypt(commandCounter.frame(payload: payload), key: key, iv: tagNonce)
            guard encrypted.count <= peripheral.maximumWriteValueLength(for: .withResponse) else { throw TagProtocolError.invalidLength }
            if kind == .stop {
                guard ringProgress.stopDispatched(generation: generation, trialID: trial) else { return }
            }
            pendingRingWrite = kind
            peripheral.writeValue(encrypted, for: characteristic, type: .withResponse)
            if kind == .start {
                let now = ProcessInfo.processInfo.systemUptime
                guard ringProgress.startDispatched(now: now, generation: generation, trialID: trial) else { return }
                ringStatus = "Inicio solicitado; parada automática solicitada a los 5 s."
                log("Sonido: START enviado; límite automático 5 s desde este envío, volumen sin modificar.")
                cancelTimeout()
                armRingAutoStop(generation: generation, trial: trial)
            } else {
                log("Sonido: STOP enviado; plazo de confirmación 3 s.")
                armTimeout(.stopAcknowledgement)
            }
        } catch { finishUnconfirmedRingStop() }
    }

    private func armRingAutoStop(generation: UInt64, trial: UUID) {
        ringAutoStop?.cancel()
        guard let deadline = ringProgress.deadline else { return }
        ringAutoStop = Task { [weak self] in
            while !Task.isCancelled {
                let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
                if delay > 0 {
                    do { try await Task.sleep(nanoseconds: UInt64(ceil(delay * 1_000_000_000))) } catch { return }
                }
                guard !Task.isCancelled, let self, self.forRing,
                      self.connectionLifecycle.currentGeneration == generation, self.ringTrialID == trial,
                      self.ringProgress.deadline == deadline else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now < deadline { continue }
                self.log("Sonido: vencieron los 5 s; se solicita STOP automático.")
                self.performRing(self.ringProgress.expiry(now: now, generation: generation, trialID: trial))
                return
            }
        }
    }

    private func didWriteRing(error: Error?) {
        guard forRing, let pending = pendingRingWrite,
              let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID else { return }
        pendingRingWrite = nil
        if pending == .start {
            log(error == nil ? "Sonido: START confirmado por Bluetooth; no confirma sonido audible." : "Sonido: START sin confirmar; se intenta STOP igualmente.")
            performRing(ringProgress.startWriteCompleted(success: error == nil, generation: generation, trialID: trial))
        } else {
            log(error == nil ? "Sonido: STOP confirmado por Bluetooth." : "Sonido: escritura STOP sin confirmar.")
            performRing(ringProgress.stopWriteCompleted(success: error == nil, generation: generation, trialID: trial))
        }
    }

    private func finishUnconfirmedRingStop() {
        guard forRing else { return }
        log("Sonido: no se completó el envío o la confirmación de parada.")
        if let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID {
            let action = ringProgress.stopWriteCompleted(success: false, generation: generation, trialID: trial)
            if action == .close { performRing(action); return }
        }
        ringStatus = "No se confirmó que el sonido se haya detenido."; log(ringStatus)
        finishDisconnect()
    }

    private func receiveRingStatus(_ characteristic: CBCharacteristic, error: Error?) {
        guard forRing, proofVerified, let credentials, let tagNonce,
              let generation = connectionLifecycle.currentGeneration, let trial = ringTrialID else { return }
        guard error == nil, let value = characteristic.value else { log("Sonido: notificación no disponible."); return }
        switch RingNotificationInspector.inspect(ciphertext: value, master: credentials.masterSecret, tagNonce: tagNonce, replay: &replay) {
        case .accepted(let isRinging):
            ringProgress.observeStatus(isRinging: isRinging, generation: generation, trialID: trial)
            ringStatus = isRinging ? "La etiqueta notificó sonido activo." : "La etiqueta notificó sonido detenido."
            log(ringStatus)
        case .unknownPayload: log("Sonido: estado desconocido, sin interpretar.")
        case .invalidCiphertext, .invalidFrame, .replayRejected:
            log("Sonido: notificación descartada por cifrado, trama o secuencia no válidos.")
        }
    }
}
