import Foundation

public enum UWBFailureStage: Equatable {
    case appleDecode
    case samsungTranslation
}

/// Deliberately excludes identifiers, addresses, STS material and opaque payloads.
public enum UWBDiagnostics {
    public static func shareableSummary(_ data: Data) -> [String] {
        let bytes = [UInt8](data)
        var lines = ["Configuración NI: \(bytes.count) bytes."]
        guard bytes.count >= 4 else { return lines }
        let major = u16(bytes, 0), minor = u16(bytes, 2)
        lines.append("Versión NI: \(major).\(minor).")
        guard (major == 1 && minor == 1 && bytes.count == 30) ||
              (major == 2 && minor == 0 && bytes.count == 35) else { return lines }
        lines.append("Longitud declarada: \(bytes[4]) bytes restantes.")
        lines.append("Perfil NI: canal \(bytes[12]), preámbulo \(bytes[11]), slots \(u16(bytes, 13)), duración \(u16(bytes, 15)) RSTU, intervalo \(u16(bytes, 17)) ms, control \(bytes[19]), hopping \(major == 2 ? String(bytes[34]) : "no disponible").")
        return lines
    }

    public static func rejection(_ error: Error, stage: UWBFailureStage) -> String {
        let label = stage == .appleDecode ? "decodificación Apple" : "traducción Samsung"
        let reason: String
        switch error {
        case AppleUWBProtocolError.invalidProfile: reason = "declaración de accesorio inválida"
        case AppleUWBProtocolError.invalidConfiguration: reason = "estructura, longitud o campos reservados no admitidos"
        case AppleUWBProtocolError.unsupportedVersion: reason = "versión no admitida"
        case AppleUWBProtocolError.unsupportedRadioParameters: reason = "parámetros de radio o dirección interna no admitidos"
        case SamsungUWBError.unsupportedProfile: reason = "parámetros fuera del perfil experimental"
        case SamsungUWBError.addressCollision: reason = "colisión de direcciones internas en el formato enviado"
        default: reason = "configuración no admitida"
        }
        return "Etapa: \(label). Motivo: \(reason)."
    }

    public static func unsupportedSamsungFields(_ value: AppleUWBParameters, accessoryAddress: UInt16) -> [String] {
        var fields: [String] = []
        if value.sessionID == 0 { fields.append("identificador de sesión inválido") }
        if value.channel != 9 { fields.append("canal") }
        if !(9...12).contains(value.preamble) { fields.append("preámbulo") }
        if value.slots != 6 { fields.append("slots") }
        if value.slotDurationRSTU != 2400 { fields.append("duración de slot") }
        if value.intervalMilliseconds == 0 { fields.append("intervalo") }
        if value.roundControl != 3 { fields.append("control de ronda") }
        if value.stsIV.count != 6 { fields.append("longitud de material STS") }
        if accessoryAddress == 0 || accessoryAddress == .max || value.phoneAddress == 0 ||
            value.phoneAddress == .max || accessoryAddress == value.phoneAddress {
            fields.append("direcciones internas inválidas")
        }
        return fields
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
}
