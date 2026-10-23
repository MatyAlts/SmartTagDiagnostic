import SwiftUI
import SmartTagCore

@MainActor
struct DiagnosticView: View {
    @StateObject private var account = SamsungAccountClient(isUITesting: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
    @StateObject private var bluetooth = TagBluetoothClient()
    @State private var selectedTagID: String?
    @State private var selectedCandidateID: UUID?
    @State private var localError: String?
    private var selectedTag: TagDevice? { account.devices.first { $0.id == selectedTagID } }
    private var testing: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }

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
                            bluetooth.clear(); account.signOut()
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
                                bluetooth.clear(); selectedTagID = device.id
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
                            selectedCandidateID = nil; localError = nil; bluetooth.scan()
                        }.disabled(bluetooth.isBusy || !tag.metadataReady)
                        ForEach(bluetooth.candidates) { candidate in
                            Button { selectedCandidateID = candidate.id } label: {
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
                            do { bluetooth.connect(candidateID: id, credentials: try tag.credentials()) }
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
                        Button("Desconectar y limpiar") { bluetooth.clear(); selectedCandidateID = nil }
                    }
                }
                if let message = localError ?? account.errorMessage ?? bluetooth.errorMessage {
                    Section("No se pudo completar") { Text(message).foregroundStyle(.red).accessibilityLabel("Error: \(message)") }
                }
                Section {
                    NavigationLink("Registro técnico") { EventLogView(events: bluetooth.events) }
                    NavigationLink("Acerca de la prueba") {
                        List {
                            Text("Diagnóstico experimental independiente. La aceptación del inicio de sesión en iOS y la interoperabilidad Bluetooth requieren pruebas reales.")
                            Text("Solo consulta autenticación y batería. No ofrece búsqueda UWB ni modifica el firmware.")
                            Text("Los eventos no incluyen claves ni tokens. Cerrar sesión elimina la sesión guardada y limpia la conexión.")
                        }.navigationTitle("Acerca de").navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnóstico Tag")
        }.tint(.blue)
    }
}

private struct EventLogView: View {
    let events: [String]
    var body: some View {
        List {
            if events.isEmpty { Text("Sin eventos").foregroundStyle(.secondary) }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in Text(event) }
        }.navigationTitle("Registro técnico").navigationBarTitleDisplayMode(.inline)
    }
}
