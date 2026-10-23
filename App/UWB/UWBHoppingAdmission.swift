import Foundation
import SmartTagCore

/// Requests are not negotiated results. Never force an ungranted OFF selection.
enum UWBHoppingAdmission {
    enum Failure: Error, LocalizedError, Equatable {
        case unsupportedVersion, notGranted
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion:
                return "Solo se puede solicitar hopping desactivado con el perfil 2.0."
            case .notGranted:
                return "Solicitud no concedida: Apple seleccionó hopping activado aunque se solicitó desactivado. Se detuvo la prueba antes de enviar parámetros UWB a la etiqueta."
            }
        }
    }

    static func validateRequest(version: AppleUWBVersion, requestedHopping: Bool) throws {
        guard version == .v2 || requestedHopping else { throw Failure.unsupportedVersion }
    }

    static func prepareAndSend(parameters: AppleUWBParameters, accessoryAddress: UInt16,
                               addressMode: SamsungUWBAddressMode = .baseline,
                               requestedHopping: Bool = true, sendConfiguration: (Data) -> Void) throws {
        try validateRequest(version: parameters.version, requestedHopping: requestedHopping)
        guard requestedHopping || !parameters.hopping else { throw Failure.notGranted }
        let translated = try SamsungUWBProtocol.configuration(parameters: parameters,
            accessoryAddress: accessoryAddress, addressMode: addressMode)
        sendConfiguration(translated)
    }
}
