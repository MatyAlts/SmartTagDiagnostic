import Foundation

public enum SamsungUWBError: Error, LocalizedError {
    case unsupportedProfile
    case addressCollision
    public var errorDescription: String? {
        switch self {
        case .unsupportedProfile:
            return "Los parámetros UWB generados por el iPhone no coinciden con el perfil experimental de la etiqueta."
        case .addressCollision:
            return "Las direcciones internas coinciden en el formato enviado."
        }
    }
}

/// Changes only Samsung's address-byte emission; Apple numeric parameters stay unchanged.
public enum SamsungUWBAddressMode: Hashable, CaseIterable {
    case baseline, accessoryLittleEndian, phoneLittleEndian, bothLittleEndian
}

/// Translation for one explicit experimental profile, not a general FiRa encoder.
public enum SamsungUWBProtocol {
    public static func configuration(parameters: AppleUWBParameters, accessoryAddress: UInt16,
                                     addressMode: SamsungUWBAddressMode = .baseline) throws -> Data {
        guard parameters.sessionID != 0,
              parameters.channel == 9, (9...12).contains(parameters.preamble),
              parameters.slots == 6, parameters.slotDurationRSTU == 2400,
              parameters.intervalMilliseconds > 0, parameters.roundControl == 3,
              parameters.stsIV.count == 6,
              accessoryAddress != 0, accessoryAddress != .max,
              parameters.phoneAddress != 0, parameters.phoneAddress != .max,
              accessoryAddress != parameters.phoneAddress else {
            throw SamsungUWBError.unsupportedProfile
        }

        let accessoryWire = addressMode == .accessoryLittleEndian || addressMode == .bothLittleEndian
            ? accessoryAddress.byteSwapped : accessoryAddress
        let phoneWire = addressMode == .phoneLittleEndian || addressMode == .bothLittleEndian
            ? parameters.phoneAddress.byteSwapped : parameters.phoneAddress
        guard accessoryWire != phoneWire else { throw SamsungUWBError.addressCollision }

        // LSB-first packed fields reconstructed from uTag's LengthByteArray.
        // Byte 3 includes SFD_ID_VALUE_2=2 at global bit 30 (mask 0x80).
        var packet = Data([0, 0x2f, 0x0c, 0x9c, parameters.hopping ? 0x05 : 0x01])
        packet.append(contentsOf: (0..<4).reversed().map {
            UInt8(truncatingIfNeeded: parameters.sessionID >> ($0 * 8))
        })
        appendBigEndian(accessoryWire, to: &packet)
        appendBigEndian(phoneWire, to: &packet)
        packet.append(parameters.channel)
        // Source pair: Android 2400 RSTU, Samsung packet field 2000.
        // Its unit conversion remains a declared interoperability hypothesis.
        appendBigEndian(2000, to: &packet)
        appendBigEndian(parameters.intervalMilliseconds, to: &packet)
        packet.append(contentsOf: [3, parameters.preamble, 1, 5])
        // Apple uses vendor 0x004c; replacing Samsung/uTag's zero is experimental.
        appendBigEndian(0x004c, to: &packet)
        packet.append(parameters.stsIV)
        packet.append(contentsOf: [6, 0, 0, 0, 0])
        return packet
    }

    private static func appendBigEndian(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
}
