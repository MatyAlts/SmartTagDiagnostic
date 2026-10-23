import SwiftUI
import SmartTagCore

@MainActor
struct DiagnosticView: View {
    @StateObject private var account = SamsungAccountClient(isUITesting: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    @StateObject private var bluetooth = TagBluetoothClient()
    @StateObject private var nearby = NearbyInteractionClient()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTagID: String?
    @State private var selectedCandidateID: UUID?
    @State private var localError: String?
    @State private var selectedUWBProfile = 2
    @State private var selectedAddressMode: SamsungUWBAddressMode = .baseline
    @State private var requestedHopping = true
    @State private var activeNIAttemptID: UUID?
    private var selectedTag: TagDevice? { account.devices.first { $0.id == selectedTagID } }
    private var testing: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    private var uwbVersion: AppleUWBVersion {
        if #available(iOS 26.1, *), selectedUWBProfile == 2 { return .v2 }
        return .v1
    }

    private func stopUWB() {
        activeNIAttemptID = nil
        nearby.stop()
        bluetooth.stopUWB()
    }

    private func metadataProblem(_ device: TagDevice) -> String {
        do {
            _ = try device.credentials()
            return "Los datos de la etiqueta están disponibles."
        } catch let error as AccountError {
            return error.localizedDescription
        } catch let error as TagProtocolError {
            return error.localizedDescription
        } catch {
            return "No se pudieron validar los datos de esta etiqueta."
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Cuenta Samsung") {
                    Label(account.isSignedIn ? "Sesión iniciada" : "Sin sesión", systemImage: "person.crop.circle")
                    Text(account.status).foregroundStyle(.secondary)
                    if account.isSignedIn {
                        Button("Actualizar etiquetas") { Task { await account.loadDevices() } }
                            .disabled(account.isBusy || bluetooth.isBusy)
                        Button("Cerrar sesión", role: .destructive) {
                            stopUWB(); bluetooth.clear(); account.signOut()
                            selectedTagID = nil; selectedCandidateID = nil; localError = nil
                        }
                    } else {
                        Button("Iniciar sesión con Samsung") { Task { if !testing { await account.signIn() } } }
                            .disabled(account.isBusy || testing)
                    }
                    if account.isBusy { ProgressView("Consultando cuenta…") }
                }
                if account.isSignedIn {
                    Section("Tu etiqueta") {
                        if account.devices.isEmpty {
                            Text("No hay etiquetas disponibles. Actualizá la lista o verificá la cuenta.").foregroundStyle(.secondary)
                        }
                        ForEach(account.devices) { device in
                            Button {
                                stopUWB(); bluetooth.clear(); selectedTagID = device.id
                                selectedCandidateID = nil; localError = nil
                            } label: {
                                HStack {
                                    Label(device.name, systemImage: "tag")
                                    Spacer()
                                    if selectedTagID == device.id { Image(systemName: "checkmark").accessibilityLabel("Seleccionada") }
                                }
                            }.disabled(bluetooth.isBusy)
                            if selectedTagID == device.id && !device.metadataReady {
                                Text(metadataProblem(device)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let tag = selectedTag {
                    Section("Prueba Bluetooth") {
                        Button("Buscar dispositivos cercanos") {
                            stopUWB(); selectedCandidateID = nil; localError = nil; bluetooth.scan()
                        }.disabled(bluetooth.isBusy || !tag.metadataReady)
                        ForEach(bluetooth.candidates) { candidate in
                            Button { stopUWB(); selectedCandidateID = candidate.id } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(candidate.name)
                                        Text("Señal: \(candidate.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedCandidateID == candidate.id {
                                        Image(systemName: "checkmark").accessibilityLabel("Periférico seleccionado")
                                    }
                                }
                            }.disabled(bluetooth.isBusy)
                        }
                        Button("Autenticar y leer batería") {
                            guard let id = selectedCandidateID else { return }
                            do { stopUWB(); bluetooth.connect(candidateID: id, credentials: try tag.credentials()) }
                            catch { localError = "No se pudo preparar la autenticación: \(error.localizedDescription)" }
                        }.disabled(bluetooth.isBusy || selectedCandidateID == nil || !tag.metadataReady)
                        if bluetooth.isBusy { ProgressView("Procesando Bluetooth…") }
                        Text(String(describing: bluetooth.phase)).foregroundStyle(.secondary)
                        if let battery = bluetooth.battery {
                            LabeledContent("Batería", value: battery.label)
                                .accessibilityIdentifier("batteryResult")
                        } else {
                            Text("Todavía no hay una lectura de batería.").foregroundStyle(.secondary)
                        }
                        Button("Desconectar y limpiar") { nearby.clear(); bluetooth.clear(); selectedCandidateID = nil }
                    }
                    Section {
                        if #available(iOS 26.1, *) {
                            Picker("Perfil experimental", selection: $selectedUWBProfile) {
                                Text("1.1").tag(1)
                                Text("2.0").tag(2)
                            }.disabled(bluetooth.isBusy || nearby.isRunning)
                        }
                        Toggle("Solicitud hopping", isOn: $requestedHopping)
                            .disabled(uwbVersion != .v2 || bluetooth.isBusy || nearby.isRunning)
                            .accessibilityIdentifier("requestedHopping")
                        Picker("Ensayo de direcciones", selection: $selectedAddressMode) {
                            Text("Base (sin invertir)").tag(SamsungUWBAddressMode.baseline)
                            Text("Solo etiqueta invertida").tag(SamsungUWBAddressMode.accessoryLittleEndian)
                            Text("Solo iPhone invertido").tag(SamsungUWBAddressMode.phoneLittleEndian)
                            Text("Ambas invertidas").tag(SamsungUWBAddressMode.bothLittleEndian)
                        }.disabled(bluetooth.isBusy || nearby.isRunning)
                        Button("Iniciar prueba UWB") {
                            guard let id = selectedCandidateID else { return }
                            nearby.clear(); localError = nil
                            do { bluetooth.connect(candidateID: id, credentials: try tag.credentials(), forUWB: true) }
                            catch { localError = "No se pudo preparar la prueba UWB." }
                        }
                        .disabled(testing || !nearby.supportsUWB || bluetooth.isBusy || nearby.isRunning || selectedCandidateID == nil || !tag.metadataReady)
                        .accessibilityIdentifier("startUWB")
                        Button("Detener prueba UWB") { stopUWB() }
                            .disabled(!nearby.isRunning && !bluetooth.uwbReady && !bluetooth.uwbActive)
                        Text(nearby.phase).foregroundStyle(.secondary)
                        if let distance = nearby.distanceMeters {
                            LabeledContent("Distancia UWB") {
                                Text(distance, format: .number.precision(.fractionLength(2))) + Text(" m")
                            }.accessibilityIdentifier("uwbDistance")
                        } else {
                            Text("Sin medición de distancia").foregroundStyle(.secondary)
                        }
                        if !nearby.supportsUWB {
                            Text("Este dispositivo no admite medición precisa UWB.").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Prueba experimental UWB")
                    } footer: {
                        Text("Mantené la app abierta. Solicitud hopping solo se puede cambiar con el perfil 2.0; Apple selecciona el resultado. Los ensayos no son correcciones verificadas. Detené la prueba antes de cambiar opciones. Solo se muestran metros recibidos de Nearby Interaction.")
                    }
                }
                if let message = localError ?? account.errorMessage ?? bluetooth.errorMessage ?? nearby.errorMessage {
                    Section("No se pudo completar") { Text(message).foregroundStyle(.red).accessibilityLabel("Error: \(message)") }
                }
                Section {
                    NavigationLink("Registro técnico") { EventLogView(bluetoothEvents: bluetooth.events, nearbyEvents: nearby.events) }
                    NavigationLink("Acerca de la prueba") {
                        List {
                            Text("Diagnóstico experimental independiente. La aceptación del inicio de sesión en iOS y la interoperabilidad Bluetooth requieren pruebas reales.")
                            Text("Consulta autenticación y batería e incluye una prueba experimental UWB. La compatibilidad UWB con la etiqueta todavía no está demostrada. No modifica el firmware.")
                            Text("Los eventos no incluyen claves ni tokens. Cerrar sesión elimina la sesión guardada y limpia la conexión.")
                        }.navigationTitle("Acerca de").navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnóstico Tag")
        }.tint(.blue)
        .onChange(of: bluetooth.uwbReady) { _, ready in
            if ready {
                nearby.start(version: uwbVersion, addressMode: selectedAddressMode, requestedHopping: requestedHopping,
                             sendConfiguration: { bluetooth.sendUWBConfiguration($0) },
                             acceptDistance: { bluetooth.acceptUWBDistance($0) },
                             onStop: { bluetooth.stopUWB() })
                activeNIAttemptID = nearby.attemptID
            } else if nearby.isRunning {
                activeNIAttemptID = nil
                nearby.stop()
            } else {
                activeNIAttemptID = nil
            }
        }
        .onChange(of: selectedUWBProfile) { _, profile in
            if profile != 2 { requestedHopping = true }
        }
        .onChange(of: bluetooth.uwbActive) { _, active in
            guard active, bluetooth.uwbActive, bluetooth.uwbReady, nearby.isRunning,
                  let attempt = activeNIAttemptID, attempt == nearby.attemptID else { return }
            nearby.configurationAcknowledged(attemptID: attempt)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stopUWB() } }
        .onChange(of: account.isSignedIn) { _, signedIn in if !signedIn { stopUWB() } }
        .onDisappear { stopUWB() }
    }
}

private struct EventLogView: View {
    let bluetoothEvents: [String]
    let nearbyEvents: [String]
    var body: some View {
        List {
            if bluetoothEvents.isEmpty && nearbyEvents.isEmpty { Text("Sin eventos").foregroundStyle(.secondary) }
            if !bluetoothEvents.isEmpty {
                Section("Bluetooth") {
                    ForEach(Array(bluetoothEvents.enumerated()), id: \.offset) { _, event in Text(event) }
                }
            }
            if !nearbyEvents.isEmpty {
                Section("Nearby Interaction") {
                    ForEach(Array(nearbyEvents.enumerated()), id: \.offset) { _, event in Text(event) }
                }
            }
        }.navigationTitle("Registro técnico").navigationBarTitleDisplayMode(.inline)
    }
}
