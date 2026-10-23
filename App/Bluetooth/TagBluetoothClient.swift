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

/// Only authentication and an encrypted battery read are implemented here.
@MainActor final class TagBluetoothClient: NSObject, ObservableObject {
    @Published private(set) var candidates: [NearbyTag] = []
    @Published private(set) var phase = "En espera"
    @Published private(set) var isBusy = false
    @Published private(set) var battery: BatteryLevel?
    @Published private(set) var errorMessage: String?
    @Published private(set) var events: [String] = []

    private static let encryption = CBUUID(string: "EEDD5E73-6AA8-4673-8219-398A489DA87C")
    private static let nonce = CBUUID(string: "A12BE31C-5B38-4773-9B9D-3D5735233A7C")
    private static let proof = CBUUID(string: "4EBE81F6-B952-465E-9ECE-5CA39D4E8955")
    private static let service = CBUUID(string: "FD5A")
    private static let batteryID = CBUUID(string: "DEE30004-182D-5496-B1AD-14F216324184")
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

    func connect(candidateID: UUID, credentials: TagCredentials) {
        guard peripheral == nil, let candidate = found[candidateID], let central, central.state == .poweredOn else {
            fail("Seleccioná una etiqueta detectada con Bluetooth disponible."); return
        }
        central.stopScan(); timeout?.cancel()
        resetHandshake(); self.credentials = credentials; battery = nil; errorMessage = nil
        var random = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            fail("No se pudieron generar datos aleatorios seguros."); return
        }
        phoneNonce = Data(random); peripheral = candidate; candidate.delegate = self
        isBusy = true; phase = "Conectando"; central.connect(candidate)
        armTimeout(); log("Conectando con el dispositivo seleccionado.")
    }

    func disconnect() {
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
    }
    private func log(_ message: String) {
        events.append(message)
        if events.count > 100 { events.removeFirst(events.count - 100) }
    }
    private func fail(_ message: String) {
        disconnect(); errorMessage = message; phase = "Detenido"; log(message)
    }
    private func armTimeout(seconds: UInt64 = 15, scanning: Bool = false) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) } catch { return }
            guard let self else { return }
            if scanning {
                self.central?.stopScan(); self.isBusy = false; self.phase = "Seleccioná una etiqueta cercana"
                self.log("Búsqueda finalizada.")
            } else { self.fail("Se agotó el tiempo de la operación Bluetooth.") }
        }
    }

    private func beginSubscriptionsIfReady() {
        guard let peripheral, let nonce = characteristics[Self.nonce],
              let proof = characteristics[Self.proof], characteristics[Self.batteryID] != nil else { return }
        guard nonce.properties.contains(.write), proof.properties.contains(.write),
              nonce.properties.contains(.notify) || nonce.properties.contains(.indicate),
              proof.properties.contains(.notify) || proof.properties.contains(.indicate),
              characteristics[Self.batteryID]!.properties.contains(.read) else {
            fail("Las operaciones GATT necesarias no están disponibles."); return
        }
        phase = "Preparando las notificaciones de autenticación"; peripheral.setNotifyValue(true, for: nonce); armTimeout()
    }

    private func advanceAuthentication(_ event: AuthenticationProgress.Event) {
        guard let peripheral, let credentials else { return }
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
        guard self.peripheral === peripheral else { return }; fail("La etiqueta se desconectó.")
    }
}

extension TagBluetoothClient: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil, let services = peripheral.services,
              services.contains(where: { $0.uuid == Self.encryption }),
              services.contains(where: { $0.uuid == Self.service }) else { fail("No se encontraron los servicios de la etiqueta."); return }
        for service in services {
            peripheral.discoverCharacteristics(service.uuid == Self.encryption ? [Self.nonce, Self.proof] : [Self.batteryID], for: service)
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
        guard error == nil, characteristic.isNotifying else { fail("Falló la suscripción a notificaciones de autenticación."); return }
        if characteristic.uuid == Self.nonce, let proof = characteristics[Self.proof] {
            peripheral.setNotifyValue(true, for: proof); armTimeout()
        } else if characteristic.uuid == Self.proof, let nonce = characteristics[Self.nonce] {
            phase = "Intercambiando valores de autenticación"; peripheral.writeValue(phoneNonce, for: nonce, type: .withResponse); armTimeout()
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
        guard error == nil else { fail("La etiqueta rechazó la escritura de autenticación."); return }
        if characteristic.uuid == Self.nonce { advanceAuthentication(.nonceWritten) }
        if characteristic.uuid == Self.proof { advanceAuthentication(.proofWritten) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral === peripheral else { return }
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
                disconnect(); battery = level; phase = "Lectura de batería completada"; log("Se completó la lectura autenticada de batería.")
            default: break
            }
        } catch {
            fail((error as? TagProtocolError)?.errorDescription ?? "La respuesta cifrada de la etiqueta no es válida.")
        }
    }
}
