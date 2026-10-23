import Foundation
import CryptoKit
import CommonCrypto

public enum TagProtocolError: Error, LocalizedError {
    case invalidHex, invalidCredentials, unsupportedCipher, invalidLength, cryptography, incorrectProof, replay, invalidBattery
    public var errorDescription: String? {
        switch self {
        case .invalidHex: return "Los datos hexadecimales no son válidos."
        case .invalidCredentials: return "La etiqueta requiere un identificador y una clave secreta de 16 bytes."
        case .unsupportedCipher: return "El cifrado de esta etiqueta no es compatible. Se detuvo el diagnóstico."
        case .invalidLength: return "El mensaje Bluetooth tiene una longitud inesperada."
        case .cryptography: return "No se pudo procesar el mensaje cifrado."
        case .incorrectProof: return "Se rechazó la prueba de autenticación de la etiqueta."
        case .replay: return "Se rechazó un mensaje repetido o fuera de orden."
        case .invalidBattery: return "La respuesta de batería es desconocida."
        }
    }
}

public struct TagCredentials {
    public let deviceID: String
    public let masterSecret: Data
    public let cipher: String
    public let advertisingID: String?
    public init(deviceID: String, masterSecret: Data, cipher: String, advertisingID: String? = nil) throws {
        guard !deviceID.isEmpty, masterSecret.count == 16 else { throw TagProtocolError.invalidCredentials }
        guard ["AES/CBC/PKCS5PADDING", "AES/CBC/PKCS7PADDING"].contains(cipher.uppercased()) else {
            throw TagProtocolError.unsupportedCipher
        }
        self.deviceID = deviceID; self.masterSecret = masterSecret
        self.cipher = cipher; self.advertisingID = advertisingID
    }
}

public extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2), hex.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { throw TagProtocolError.invalidHex }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { throw TagProtocolError.invalidHex }
            append(byte); index = end
        }
    }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

public enum SmartTagCrypto {
    public static func derive(master: Data, context: Data) -> Data {
        Data(SHA256.hash(data: master + Data([0,0,0,1]) + context).prefix(16))
    }
    public static func encrypt(_ input: Data, key: Data, iv: Data) throws -> Data {
        try crypt(input, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
    }
    public static func decrypt(_ input: Data, key: Data, iv: Data) throws -> Data {
        guard !input.isEmpty, input.count.isMultiple(of: 16) else { throw TagProtocolError.invalidLength }
        return try crypt(input, key: key, iv: iv, operation: CCOperation(kCCDecrypt))
    }
    private static func crypt(_ input: Data, key: Data, iv: Data, operation: CCOperation) throws -> Data {
        guard key.count == 16, iv.count == 16 else { throw TagProtocolError.invalidLength }
        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inputBytes.baseAddress, input.count, outputBytes.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw TagProtocolError.cryptography }
        output.count = written
        return output
    }
    public static func verifyProof(_ encrypted: Data, key: Data, phoneNonce: Data) throws {
        let actual = try decrypt(encrypted, key: key, iv: phoneNonce)
        let expected = Data("smartthings".utf8)
        guard actual.count == expected.count else { throw TagProtocolError.incorrectProof }
        let difference = zip(actual, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) }
        guard difference == 0 else { throw TagProtocolError.incorrectProof }
    }
}

public struct SmartTagFrame {
    public let counter: UInt32
    public let payload: Data
    public init(counter: UInt32, payload: Data) { self.counter = counter; self.payload = payload }
    public var encoded: Data {
        Data((0..<4).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) }) + payload
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count >= 5 else { throw TagProtocolError.invalidLength }
        let bytes = Array(data)
        let counter = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[$1]) << ($1 * 8) }
        return Self(counter: counter, payload: Data(bytes.dropFirst(4)))
    }
}

public struct ReplayCounter {
    private var previous: UInt32?
    public init() {}
    public mutating func accept(_ value: UInt32) throws {
        if let previous, value <= previous { throw TagProtocolError.replay }
        previous = value
    }
}

public enum BatteryLevel: UInt8, CaseIterable {
    case veryLow = 0, low = 1, sufficient = 2, full = 3
    public var label: String {
        switch self { case .veryLow: return "Muy baja"; case .low: return "Baja"
        case .sufficient: return "Suficiente"; case .full: return "Llena" }
    }
    public static func decode(_ payload: Data) throws -> Self {
        guard payload.count == 1, let byte = payload.first, let level = Self(rawValue: byte) else {
            throw TagProtocolError.invalidBattery
        }
        return level
    }
}
