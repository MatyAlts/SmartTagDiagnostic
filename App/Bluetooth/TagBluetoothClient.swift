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

/// Battery-only remains the default; UWB requires a separate explicit connection.
@MainActor final class TagBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var candidates: [NearbyTag] = []
    @Published private(set) var phase = "En espera"
    @Published private(set) var isBusy = false
    @Published private(set) var battery: BatteryLevel?
    @Published private(set) var errorMessage: String?
    @Published private(set) var events: [String] = []
    @Published private(set) var uwbReady = false
    @Published private(set) var uwbActive = false

    private static let encryption = CBUUID(string: "EEDD5E73-6AA8-4673-8219-398A489DA87C")
    private static let nonce = CBUUID(string: "A12BE31C-5B38-4773-9B9D-3D5735233A7C")
    private static let proof = CBUUID(string: "4EBE81F6-B952-465E-9ECE-5CA39D4E8955")
    private static let service = CBUUID(string: "FD5A")
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
    private var replay = ReplayCounter()
    private var forUWB = false
    private var subscriptionsStarted = false
    private var uwbFlow = UWBExperimentFlow()
    private var commandCounter = UWBCommandCounter()
    private enum UWBWrite: Equatable { case start, configuration, stop }
    private var pendingUWBWrite: UWBWrite?
    private var queuedStop = false

    override init() {
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
        armTimeout(seconds: 12, scanning: true)
        log("Búsqueda iniciada. Seleccioná tu etiqueta; la autenticación comprobará su identidad.")
    }

    func connect(candidateID: UUID, credentials: TagCredentials, forUWB: Bool = false) {
        guard peripheral == nil, let candidate = found[candidateID], let central, central.state == .poweredOn else {
            fail("Seleccioná una etiqueta detectada con Bluetooth disponible."); return
        }
        central.stopScan(); timeout?.cancel()
        resetHandshake(); self.forUWB = forUWB
        self.credentials = credentials; battery = nil; errorMessage = nil
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            fail("No se pudieron generar datos aleatorios seguros."); return
        }
        phoneNonce = Data(random); peripheral = candidate; candidate.delegate = self
        isBusy = true; phase = "Conectando"; central.connect(candidate)
        armTimeout(); log("Conectando con el dispositivo seleccionado.")
    }

    func disconnect() {
        if forUWB { stopUWB() }
        else { finishDisconnect() }
    }

    private func finishDisconnect() {
        pendingScan = false; central?.stopScan(); timeout?.cancel()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral?.delegate = nil; peripheral = nil; credentials = nil
        resetHandshake(); authentication.cancel(); isBusy = false; phase = "Desconectado"
    }

    func clear() {
        disconnect(); errorMessage = nil; battery = nil; events = []; phase = "En espera"
    }

    private func resetHandshake() {
        phoneNonce = Data(); tagNonce = nil; characteristics = [:]
        authentication = AuthenticationProgress()
        proofVerified = false; batteryRequested = false; replay = ReplayCounter()
        subscriptionsStarted = false; forUWB = false
        uwbReady = false; uwbActive = false; uwbFlow = UWBExperimentFlow()
        commandCounter = UWBCommandCounter(); pendingUWBWrite = nil; queuedStop = false
    }
    private func log(_ message: String) {
        events.append(message)
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
    private func fail(_ message: String) {
        errorMessage = message; log(message)
        if forUWB { performUWB(uwbFlow.receive(.failure)) }
        else { finishDisconnect() }
        phase = "Detenido"
    }
    private func armTimeout(seconds: UInt64 = 15, scanning: Bool = false) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self else { return }
            if scanning {
                self.central?.stopScan(); self.isBusy = false; self.phase = "Seleccioná una etiqueta cercana"
                self.log("Búsqueda finalizada.")
            } else if self.forUWB, self.uwbFlow.state == .stopping {
                self.log("Terminó el plazo de parada UWB; se cerró la conexión.")
                self.performUWB(self.uwbFlow.receive(.timeout))
            } else { self.fail("Se agotó el tiempo de la operación Bluetooth.") }
        }
    }

    private func beginSubscriptionsIfReady() {
        guard !subscriptionsStarted, let peripheral, let nonce = characteristics[Self.nonce],
              let proof = characteristics[Self.proof], characteristics[Self.batteryID] != nil else { return }
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
            uwbReady = false; uwbActive = false; queuedStop = true
            phase = "Deteniendo UWB"; armTimeout(seconds: 3)
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
            if uwbFlow.state == .stopping { finishDisconnect() }
            else { fail("No se puede enviar la orden UWB con esta conexión.") }
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
            peripheral.writeValue(encrypted, for: characteristic, type: .withResponse)
            armTimeout(seconds: uwbFlow.state == .stopping ? 3 : 15)
        } catch {
            if uwbFlow.state == .stopping { finishDisconnect() }
            else { fail("No se pudo preparar la orden cifrada UWB.") }
        }
    }

    private func didWriteUWB(_ characteristic: CBCharacteristic, error: Error?) {
        guard let pending = pendingUWBWrite else { return }
        let expected = pending == .configuration ? Self.uwbParameters : Self.uwbControl
        guard characteristic.uuid == expected else { return }
        pendingUWBWrite = nil
        if uwbFlow.state == .stopping, pending != .stop {
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
            armTimeout(seconds: 30)
        case .stop:
            log("La escritura de parada UWB fue confirmada.")
            performUWB(uwbFlow.receive(.stopAcknowledged))
        }
    }
}

extension TagBluetoothClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if pendingScan {
            if central.state == .unknown || central.state == .resetting { return }
            pendingScan = false; isBusy = false; timeout?.cancel()
            if central.state == .poweredOn { scan() }
            else { fail("Activá Bluetooth y permití su acceso desde Ajustes.") }
            return
        }
        if central.state != .poweredOn, isBusy { fail("Bluetooth dejó de estar disponible.") }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
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
        guard self.peripheral === peripheral else { return }
        phase = "Buscando servicios"; peripheral.discoverServices([Self.encryption, Self.service]); armTimeout()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }; fail("No se pudo conectar con la etiqueta.")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard self.peripheral === peripheral else { return }
        let stopping = uwbFlow.state == .stopping
        finishDisconnect()
        if !stopping { errorMessage = "La etiqueta se desconectó."; phase = "Detenido"; log("La etiqueta se desconectó.") }
    }
}

extension TagBluetoothClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let services = peripheral.services,
              services.contains(where: { $0.uuid == Self.encryption }),
              services.contains(where: { $0.uuid == Self.service }) else { fail("No se encontraron los servicios de la etiqueta."); return }
        for service in services {
            let control = forUWB ? [Self.batteryID, Self.uwbControl, Self.uwbParameters] : [Self.batteryID]
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
        if characteristic.uuid == Self.uwbParameters {
            if forUWB { log("Se recibió un mensaje UWB de \(characteristic.value?.count ?? 0) bytes; su contenido no se interpreta.") }
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
                if forUWB, let parameters = characteristics[Self.uwbParameters] {
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
