import Foundation
import AuthenticationServices
import UIKit
import CryptoKit
import Combine
import SmartTagCore

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class SamsungAccountClient: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isBusy = false
    @Published private(set) var isSignedIn = false
    @Published private(set) var devices: [TagDevice] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var status = "Sin sesión"
    private struct Session: Codable { let server: String; var access: String; var refresh: String }
    private let vault = AccountVault()
    private let redirects = NoRedirects()
    private lazy var network: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.httpShouldSetCookies = false
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
    }()
    private var session: Session?
    private var browser: ASWebAuthenticationSession?
    private var loginID: UUID?
    private var generation = UUID()
    private let isUITesting: Bool

    init(isUITesting: Bool = false) {
        self.isUITesting = isUITesting
        super.init()
        guard !isUITesting else { return }
        do {
            if let saved = try vault.read("session") {
                let decoded = try JSONDecoder().decode(Session.self, from: saved)
                _ = try SamsungAuth.server(decoded.server)
                session = decoded; isSignedIn = true; status = "Sesión guardada; pendiente de verificar"
            }
        } catch { errorMessage = "No se pudo restaurar la sesión segura." }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func signOut() {
        generation = UUID()
        loginID = nil; browser?.cancel(); browser = nil
        session = nil; devices = []; isSignedIn = false; isBusy = false
        guard !isUITesting else { status = "Sin sesión"; return }
        do { try vault.removeSession(); errorMessage = nil; status = "Sesión local eliminada" }
        catch { errorMessage = "La sesión se cerró en memoria, pero no se pudo eliminar del llavero." }
    }
    private func request(_ url: URL, fields: [String:String]? = nil, bearer: String? = nil, v7: Bool = false) async throws -> [String:Any] {
        guard !isUITesting else { throw AccountError.cancelled }
        let operation = generation
        var request = URLRequest(url: url)
        request.setValue(v7 ? "application/vnd.smartthings+json;v=7" : "application/json", forHTTPHeaderField: "Accept")
        if !v7 {
            // Source-derived Android OSP compatibility profile, not a registered iOS client.
            request.setValue("35", forHTTPHeaderField: "X-Osp-Clientosversion")
            request.setValue("iPhone", forHTTPHeaderField: "X-Osp-Clientmodel")
            request.setValue(SamsungAuth.loginClientID, forHTTPHeaderField: "X-Osp-Appid")
            request.setValue("com.samsung.android.oneconnect", forHTTPHeaderField: "X-Osp-Packagename")
            request.setValue("1.8.52.23", forHTTPHeaderField: "X-Osp-Packageversion")
            request.setValue("Android/Oneapp/1.8.52.23 (iPhone; Android 35/15) 4.11.0 QcApplication", forHTTPHeaderField: "User-Agent")
        }
        if let fields {
            request.httpMethod = "POST"; request.httpBody = SamsungAuth.form(fields)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await network.data(for: request)
        guard operation == generation else { throw AccountError.cancelled }
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AccountError.http(http.statusCode) }
        guard data.count <= 8_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw AccountError.invalidResponse }
        return object
    }
    private func required(_ object: [String:Any], _ key: String) throws -> String {
        guard let value = object[key] as? String, !value.isEmpty else { throw AccountError.invalidResponse }
        return value
    }
    private func deviceID() throws -> String {
        if let data = try vault.read("device"), let id = String(data: data, encoding: .utf8) { return id }
        let id = try AccountSecurity.random(8).map { String(format: "%02x", $0) }.joined()
        try vault.write(Data(id.utf8), name: "device"); return id
    }
    func signIn() async {
        guard !isBusy else { return }
        let operation = generation
        isBusy = true; errorMessage = nil; status = "Preparando inicio de sesión Samsung"
        let attempt = UUID(); loginID = attempt
        defer { if operation == generation { isBusy = false; loginID = nil; browser = nil } }
        do {
            let entry = try await request(URL(string: "https://account.samsung.com/accounts/ANDROIDSDK/getEntryPoint")!)
            let state = try AccountSecurity.random(24).base64EncodedString()
            let verifier = try AccountSecurity.random(32).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let device = try deviceID()
            let url = try loginURL(entry: entry, state: state, verifier: verifier, device: device)
            let began = Date()
            status = "Completá el inicio de sesión en Samsung"
            let callback = try await browse(url)
            guard loginID == attempt, Date().timeIntervalSince(began) < 600 else { throw AccountError.cancelled }
            let fields = try SamsungAuth.callbackFields(callback)
            let responseKey = try AccountSecurity.decryptHex(fields["state"]!, key: state)
            let server = try SamsungAuth.server(AccountSecurity.decryptHex(fields["auth_server_url"]!, key: responseKey))
            let code = try AccountSecurity.decryptHex(fields["code"]!, key: responseKey)
            let username = try AccountSecurity.decryptHex(fields["retValue"]!, key: responseKey)
            loginID = nil // Consume the callback before any token exchange.
            status = "Solicitando sesión SmartThings"
            let auth = try await request(server.appendingPathComponent("auth/oauth2/authenticate"), fields: ["grant_type":"authorization_code","serviceType":"M","code":code,"client_id":SamsungAuth.loginClientID,"code_verifier":verifier,"username":username,"physical_address_text":device])
            let userToken = try required(auth, "userauth_token")
            var parameters = ["response_type":"code","serviceType":"M","client_id":SamsungAuth.smartThingsClientID,"code_challenge_method":"S256","childAccountSupported":"Y","userauth_token":userToken,"code_challenge":SamsungAuth.challenge(verifier),"physical_address_text":device,"scope":"iot.client","login_id":username]
            var authorization = try await authorize(server, parameters)
            if authorization["code"] == nil && authorization["privacyAccepted"] as? String == "N" {
                parameters.removeValue(forKey: "login_id"); authorization = try await self.authorize(server, parameters)
            }
            let token = try await request(server.appendingPathComponent("auth/oauth2/token"), fields: ["grant_type":"authorization_code","code":try required(authorization,"code"),"client_id":SamsungAuth.smartThingsClientID,"code_verifier":verifier,"physical_address_text":device])
            session = Session(server: server.absoluteString, access: try required(token,"access_token"), refresh: try required(token,"refresh_token"))
            try save(); isSignedIn = true
            try await fetchDevices(); status = "Cuenta conectada"
        } catch { if operation == generation { errorMessage = diagnostic(error); status = "No se completó el inicio de sesión" } }
    }
    private func authorize(_ server: URL, _ fields: [String:String]) async throws -> [String:Any] {
        var parts = URLComponents(url: server.appendingPathComponent("auth/oauth2/v2/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = SamsungAuth.queryURL(parts) else { throw AccountError.invalidResponse }
        return try await request(url)
    }
    private func save() throws {
        guard let session else { throw AccountError.invalidResponse }
        try vault.write(JSONEncoder().encode(session), name: "session")
    }
    private func refresh() async throws {
        guard let old = session else { throw AccountError.cancelled }
        let server = try SamsungAuth.server(old.server)
        let result = try await request(server.appendingPathComponent("auth/oauth2/token"), fields: ["grant_type":"refresh_token","client_id":SamsungAuth.smartThingsClientID,"refresh_token":old.refresh])
        session = Session(server: old.server, access: try required(result,"access_token"), refresh: try required(result,"refresh_token")); try save()
    }
    func loadDevices() async {
        guard !isBusy else { return }; isBusy = true; errorMessage = nil
        let operation = generation
        defer { if operation == generation { isBusy = false } }
        do { try await fetchDevices(); status = "Etiquetas consultadas" }
        catch { if operation == generation { errorMessage = diagnostic(error) } }
    }
    private func authenticated(_ url: URL) async throws -> [String:Any] {
        guard let session else { throw AccountError.cancelled }
        do { return try await request(url, bearer: session.access, v7: true) }
        catch AccountError.http(401) {
            try await refresh()
            guard let updated = self.session else { throw AccountError.cancelled }
            return try await request(url, bearer: updated.access, v7: true)
        }
    }
    private func fetchDevices() async throws {
        let base = URL(string: "https://client.smartthings.com/devices?includeAllowedActions=true")!
        var next: URL? = base; var visited = Set<String>(); var found: [TagDevice] = []
        while let url = next {
            guard visited.insert(url.absoluteString).inserted, visited.count <= 100 else { throw AccountError.invalidResponse }
            let page = try await authenticated(url)
            guard let items = page["items"] as? [[String:Any]] else { throw AccountError.invalidResponse }
            found.append(contentsOf: items.compactMap(TagDevice.init(json:)))
            if let href = ((page["_links"] as? [String:Any])?["next"] as? [String:Any])?["href"] as? String { next = try SamsungAuth.page(href, relativeTo: url) }
            else { next = nil }
        }
        // Detail endpoint may expose BLE fields omitted from the list. Only query account-listed tags.
        var detailed: [TagDevice] = []
        for tag in found {
            var c = URLComponents(string: "https://client.smartthings.com")!
            c.path = "/devices/" + tag.id; c.queryItems = [URLQueryItem(name:"includeAllowedActions",value:"true")]
            guard let url = c.url else { throw AccountError.invalidResponse }
            let object = try await authenticated(url)
            detailed.append(TagDevice(json: object) ?? tag)
        }
        devices = detailed
    }
    private func browse(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let web = ASWebAuthenticationSession(url: url, callbackURLScheme: "ms-app") { callback, _ in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: AccountError.cancelled) }
            }
            web.presentationContextProvider = self; web.prefersEphemeralWebBrowserSession = true
            browser = web
            if !web.start() { continuation.resume(throwing: AccountError.cancelled) }
        }
    }
    private func diagnostic(_ error: Error) -> String {
        // Never use NSError descriptions: URLs can contain userauth_token or callback secrets.
        (error as? AccountError)?.errorDescription ?? "Falló la conexión o el procesamiento de la respuesta. No se registraron datos sensibles."
    }
    private func loginURL(entry: [String:Any], state: String, verifier: String, device: String) throws -> URL {
        let signIn = try required(entry,"signInURI")
        guard let endpoint = URLComponents(string: signIn), let host = endpoint.host else { throw AccountError.unsafeURL }
        _ = try SamsungAuth.server("https://" + host)
        guard endpoint.scheme == "https", endpoint.user == nil, endpoint.password == nil, endpoint.port == nil,
              let publicKey = Data(base64Encoded: try required(entry,"pkiPublicKey")) else { throw AccountError.unsafeURL }
        let check = try required(entry,"chkDoNum")
        guard let count = Int(check), count > 0, count <= 1_000_000 else { throw AccountError.invalidResponse }
        // PBKDF2 construction matches SignInUtils; salt is random for each request.
        let salt = try AccountSecurity.random(16)
        let password = Data(SHA256.hash(data: Data(check.utf8))).base64EncodedString()
        let aesKey = try AccountSecurity.derive(password: password, salt: salt, iterations: count)
        let iv = try AccountSecurity.random(16)
        let parameters = ["clientId":SamsungAuth.loginClientID,"code_challenge":SamsungAuth.challenge(verifier),"code_challenge_method":"S256","competitorDeviceYNFlag":"Y","countryCode":Locale.current.region?.identifier.lowercased() ?? "us","deviceInfo":"Apple|com.android.chrome","deviceModelID":UIDevice.current.model,"deviceName":"iPhone SmartTag Diagnostic","deviceOSVersion":UIDevice.current.systemVersion,"devicePhysicalAddressText":"ANID:"+device,"deviceType":"APP","deviceUniqueID":device,"redirect_uri":SamsungAuth.redirect,"replaceableClientConnectYN":"N","replaceableClientId":"","replaceableDevicePhysicalAddressText":"","responseEncryptionType":"1","responseEncryptionYNFlag":"Y","scope":"","state":state,"svcIptLgnID":"","iosYNFlag":"Y"]
        let encrypted = try AccountSecurity.crypt(JSONSerialization.data(withJSONObject: parameters), key: aesKey, iv: iv)
        let envelope = ["chkDoNum":check,"svcEncParam":encrypted.base64EncodedString(),"svcEncKY":try AccountSecurity.rsaWrap(Data(aesKey.base64EncodedString().utf8), spki: publicKey).base64EncodedString(),"svcEncIV":iv.map { String(format:"%02x",$0) }.joined()]
        var parts = endpoint
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name:"locale",value:Locale.current.identifier.replacingOccurrences(of:"_",with:"-")),URLQueryItem(name:"svcParam",value:try JSONSerialization.data(withJSONObject: envelope).base64EncodedString()),URLQueryItem(name:"mode",value:"C")]
        guard let url = SamsungAuth.queryURL(parts) else { throw AccountError.invalidResponse }; return url
    }
}
