import Foundation
import Security
import CommonCrypto
import SmartTagCore

enum AccountSecurity {
    static func derive(password: String, salt: Data, iterations: Int) throws -> Data {
        var key = Data(count: 16)
        let status = key.withUnsafeMutableBytes { output in salt.withUnsafeBytes { s in
            password.withCString { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p, password.utf8.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), output.bindMemory(to: UInt8.self).baseAddress, 16)
            }
        } }
        guard status == kCCSuccess else { throw AccountError.invalidResponse }; return key
    }
    static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw AccountError.keyStorage }
        return data
    }
    static func crypt(_ data: Data, key: Data, iv: Data? = nil, decrypt: Bool = false) throws -> Data {
        guard key.count == 16, iv == nil || iv?.count == 16 else { throw AccountError.invalidResponse }
        let capacity = data.count + kCCBlockSizeAES128
        var output = Data(count: capacity); var count = 0
        let options = CCOptions(kCCOptionPKCS7Padding | (iv == nil ? kCCOptionECBMode : 0))
        let status = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in key.withUnsafeBytes { k in
            if let iv { return iv.withUnsafeBytes { v in CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, k.baseAddress, key.count, v.baseAddress, input.baseAddress, data.count, out.baseAddress, capacity, &count) } }
            return CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, k.baseAddress, key.count, nil, input.baseAddress, data.count, out.baseAddress, capacity, &count)
        } } }
        guard status == kCCSuccess else { throw AccountError.callback }
        return output.prefix(count)
    }
    static func decryptHex(_ text: String, key: String) throws -> String {
        // AES ciphertext must contain whole blocks, including the PKCS7 padding block.
        guard !text.isEmpty, text.count % (2 * kCCBlockSizeAES128) == 0,
              text.count <= 65536, text.allSatisfy({ $0.isHexDigit }) else { throw AccountError.callback }
        var data = Data(); var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let value = UInt8(text[index..<end], radix: 16) else { throw AccountError.callback }
            data.append(value); index = end
        }
        let keyData = Data(key.utf8.prefix(16))
        guard let result = String(data: try crypt(data, key: keyData, decrypt: true), encoding: .utf8), !result.isEmpty else { throw AccountError.callback }
        return result
    }
    // Entry point supplies X.509 SubjectPublicKeyInfo; Security expects PKCS#1 RSA.
    static func rsaWrap(_ value: Data, spki: Data) throws -> Data {
        var cursor = 0
        func element(_ bytes: Data, _ offset: inout Int, tag: UInt8) throws -> Data {
            guard offset + 2 <= bytes.count, bytes[offset] == tag else { throw AccountError.invalidResponse }
            offset += 1; var length = Int(bytes[offset]); offset += 1
            if length & 0x80 != 0 {
                let size = length & 0x7f
                guard size > 0, size <= 4, offset + size <= bytes.count else { throw AccountError.invalidResponse }
                length = 0
                for _ in 0..<size { length = length * 256 + Int(bytes[offset]); offset += 1 }
            }
            guard length <= bytes.count - offset else { throw AccountError.invalidResponse }
            defer { offset += length }
            return bytes.subdata(in: offset..<(offset + length))
        }
        let sequence = try element(spki, &cursor, tag: 0x30)
        var inner = 0; _ = try element(sequence, &inner, tag: 0x30)
        let bits = try element(sequence, &inner, tag: 0x03)
        guard bits.first == 0 else { throw AccountError.invalidResponse }
        let attributes: [CFString:Any] = [kSecAttrKeyType:kSecAttrKeyTypeRSA, kSecAttrKeyClass:kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(Data(bits.dropFirst()) as CFData, attributes as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(key, .encrypt, .rsaEncryptionPKCS1),
              let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, value as CFData, nil) else { throw AccountError.invalidResponse }
        return encrypted as Data
    }
}

final class AccountVault {
    private let service = "SmartTagDiagnostic.Account"
    func read(_ name: String) throws -> Data? {
        var result: CFTypeRef?
        let query: [CFString:Any] = [kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:name,kSecReturnData:true,kSecMatchLimit:kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AccountError.keyStorage }
        return data
    }
    func write(_ data: Data, name: String) throws {
        let query: [CFString:Any] = [kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:name]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData:data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AccountError.keyStorage }
        var item = query; item[kSecValueData] = data; item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AccountError.keyStorage }
    }
    func removeSession() throws {
        let status = SecItemDelete([kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:"session"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keyStorage }
    }
}
