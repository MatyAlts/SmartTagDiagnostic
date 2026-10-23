import Foundation
import CryptoKit

public enum AccountURLStage: String {
    case callbackServer = "retorno de Samsung (auth_server_url)"
    case entrySignIn = "apertura de Samsung (signInURI)"
    case pagination = "listado de etiquetas (paginación)"
}

public enum AccountError: Error, LocalizedError {
    case invalidResponse, unsafeURL, callback, missingMetadata, http(Int), cancelled, keyStorage
    case rejectedURL(AccountURLStage, String)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Respuesta de Samsung incompatible o incompleta."
        case .unsafeURL: return "Se rechazó una dirección de servidor inesperada."
        case .rejectedURL(let stage, let host): return "Se rechazó una dirección de servidor inesperada. Etapa: \(stage.rawValue). Servidor: \(host)."
        case .callback: return "El retorno de Samsung no coincide con el intento de inicio de sesión."
        case .missingMetadata: return "Samsung no entregó encryptionKey/cipher válidos para esta etiqueta."
        case .http(let code): return "Samsung respondió HTTP \(code). La sesión o el cliente pueden no estar autorizados."
        case .cancelled: return "Inicio de sesión cancelado o vencido."
        case .keyStorage: return "No se pudo acceder al almacenamiento seguro."
        }
    }
}

public enum SamsungAuth {
    public static let loginClientID = "yfrtglt53o"
    public static let smartThingsClientID = "6iado3s6jc"
    public static let callbackHost = "s-1-15-2-4027708247-2189610-1983755848-2937435718-1578786913-2158692839-1974417358"
    public static let redirect = "ms-app://" + callbackHost
    public static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
    // Only a conservative ASCII DNS authority may enter diagnostics. Never echo raw URLs.
    public static func rejectedURL(_ text: String, stage: AccountURLStage) -> AccountError {
        let value = text.contains("://") ? text : "https://" + text
        var hostname = "no disponible"
        if let separator = value.range(of: "://") {
            let authority = value[separator.upperBound...].prefix { !"/?#".contains($0) }
            if authority.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
               let components = URLComponents(string: value), let host = components.host?.lowercased(),
               host.utf8.count <= 253 {
                let labels = host.split(separator: ".", omittingEmptySubsequences: false)
                let valid = !labels.isEmpty && labels.allSatisfy { label in
                    !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("xn--") &&
                    label.first != "-" && label.last != "-" &&
                    label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
                }
                if valid { hostname = host }
            }
        }
        return .rejectedURL(stage, hostname)
    }
    public static func server(_ text: String, stage: AccountURLStage = .callbackServer) throws -> URL {
        let value = text.contains("://") ? text : "https://" + text
        guard let u = URLComponents(string: value), u.scheme == "https", let host = u.host?.lowercased(),
              host == "samsung.com" || host.hasSuffix(".samsung.com") ||
                (stage == .callbackServer && host == "us-auth2.samsungosp.com"),
              u.user == nil, u.password == nil, u.port == nil, u.query == nil, u.fragment == nil,
              u.path.isEmpty || u.path == "/", let url = u.url else { throw rejectedURL(text, stage: stage) }
        return url
    }
    public static func callbackFields(_ url: URL) throws -> [String: String] {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "ms-app",
              c.host == callbackHost, c.path.isEmpty || c.path == "/", c.user == nil,
              c.password == nil, c.port == nil, c.fragment == nil else { throw AccountError.callback }
        var result: [String:String] = [:]
        for item in c.queryItems ?? [] {
            guard result[item.name] == nil, let value = item.value, !value.isEmpty else { throw AccountError.callback }
            result[item.name] = value
        }
        for key in ["code", "state", "auth_server_url", "retValue"] {
            guard result[key] != nil else { throw AccountError.callback }
        }
        return result
    }
    public static func page(_ href: String, relativeTo base: URL) throws -> URL {
        let rejection = rejectedURL(URL(string: href, relativeTo: base)?.absoluteURL.absoluteString ?? "", stage: .pagination)
        guard let url = URL(string: href, relativeTo: base)?.absoluteURL,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              c.host == "client.smartthings.com", c.port == nil, c.user == nil, c.password == nil,
              c.fragment == nil, c.path == "/devices" else { throw rejection }
        var items = (c.queryItems ?? []).filter { $0.name != "includeAllowedActions" }
        items.append(URLQueryItem(name: "includeAllowedActions", value: "true")); c.queryItems = items
        guard let result = c.url else { throw rejection }; return result
    }
    public static func form(_ fields: [String:String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" +
            ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
    }
    public static func queryURL(_ components: URLComponents) -> URL? {
        var safe = components
        safe.percentEncodedQuery = safe.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return safe.url
    }
}

extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

public struct TagDevice: Identifiable {
    public let id: String
    public let name: String
    public let advertisingID: String?
    private let key: String?
    private let cipher: String?
    public var metadataReady: Bool { (try? credentials()) != nil }
    public init?(json: [String:Any]) {
        guard let id = json["deviceId"] as? String, !id.isEmpty, id.count <= 200,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) }),
              json["type"] as? String == "BLE_D2D" || (json["ocf"] as? [String:Any])?["ocfDeviceType"] as? String == "x.com.st.d.tag" else { return nil }
        self.id = id
        name = json["label"] as? String ?? json["name"] as? String ?? "SmartTag"
        let ble = json["bleD2D"] as? [String:Any] ?? [:]
        key = ble["encryptionKey"] as? String
        cipher = ble["cipher"] as? String
        advertisingID = ble["advertisingId"] as? String
    }
    public func credentials() throws -> TagCredentials {
        guard let key, let cipher, !cipher.isEmpty else { throw AccountError.missingMetadata }
        return try TagCredentials(deviceID: id, masterSecret: Self.decodeKey(key, advertisingID: advertisingID), cipher: cipher, advertisingID: advertisingID)
    }
    public static func decodeKey(_ value: String, advertisingID: String?) throws -> Data {
        let bytes: Data
        if advertisingID != nil {
            guard value.count % 2 == 0, value.allSatisfy({ $0.isHexDigit }) else { throw AccountError.missingMetadata }
            var data = Data(); var index = value.startIndex
            while index < value.endIndex {
                let next = value.index(index, offsetBy: 2)
                guard let b = UInt8(value[index..<next], radix: 16) else { throw AccountError.missingMetadata }
                data.append(b); index = next
            }
            bytes = data
        } else {
            var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            text += String(repeating: "=", count: (4 - text.count % 4) % 4)
            guard let data = Data(base64Encoded: text) else { throw AccountError.missingMetadata }
            bytes = data
        }
        guard bytes.count >= 16 else { throw AccountError.missingMetadata }
        return Data(bytes.prefix(16))
    }
}
