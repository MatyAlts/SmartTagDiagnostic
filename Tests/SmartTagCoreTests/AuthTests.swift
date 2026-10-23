import XCTest
@testable import SmartTagCore

final class AuthTests: XCTestCase {
    func testRejectedCallbackReportsOnlyHostnameAndFixedStage() {
        let error = SamsungAuth.rejectedURL("https://username:password@Regional.Example.test/private/code?token=secret#fragment", stage: .callbackServer)
        XCTAssertEqual(error.errorDescription, "Se rechazó una dirección de servidor inesperada. Etapa: retorno de Samsung (auth_server_url). Servidor: regional.example.test.")
        XCTAssertThrowsError(try SamsungAuth.server("https://regional.example.test")) { error in
            XCTAssertEqual((error as? AccountError)?.errorDescription, "Se rechazó una dirección de servidor inesperada. Etapa: retorno de Samsung (auth_server_url). Servidor: regional.example.test.")
        }
    }
    func testRejectedURLNeverEchoesMalformedOrUnicodeAuthority() {
        for input in ["https:///private?token=secret", "https://", "https://sámsung.com", "https://xn--samsung-secret.example", "https://bad%0Ahost.test/path", "https://bad\nhost.test", "https://bad_host.test", "https://-bad.test", "https://bad..test", "private token secret"] {
            XCTAssertEqual(SamsungAuth.rejectedURL(input, stage: .callbackServer).errorDescription,
                "Se rechazó una dirección de servidor inesperada. Etapa: retorno de Samsung (auth_server_url). Servidor: no disponible.", input)
        }
    }
    func testRejectionStagesStayDistinctAndDoNotChangeTrustPolicy() {
        let input = "https://regional.example.test/private?token=secret#fragment"
        XCTAssertEqual(SamsungAuth.rejectedURL(input, stage: .entrySignIn).errorDescription,
            "Se rechazó una dirección de servidor inesperada. Etapa: apertura de Samsung (signInURI). Servidor: regional.example.test.")
        let base = URL(string: "https://client.smartthings.com/devices")!
        XCTAssertThrowsError(try SamsungAuth.page(input, relativeTo: base)) { error in
            XCTAssertEqual((error as? AccountError)?.errorDescription,
                "Se rechazó una dirección de servidor inesperada. Etapa: listado de etiquetas (paginación). Servidor: regional.example.test.")
        }
        XCTAssertThrowsError(try SamsungAuth.server("https://regional.example.test", stage: .entrySignIn)) { error in
            XCTAssertTrue((error as? AccountError)?.errorDescription?.contains("apertura de Samsung (signInURI)") == true)
        }
    }
    func testPKCEPublishedVector() {
        XCTAssertEqual(SamsungAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertNotEqual(SamsungAuth.challenge("different"), SamsungAuth.challenge("other"))
    }
    func testServerOriginIsStrict() throws {
        XCTAssertEqual(try SamsungAuth.server("account.samsung.com").host, "account.samsung.com")
        for value in ["http://account.samsung.com", "https://samsung.com.evil.test", "https://user@account.samsung.com", "https://account.samsung.com:8443", "https://account.samsung.com/path"] {
            XCTAssertThrowsError(try SamsungAuth.server(value))
        }
    }
    func testMetadataKeyVariants() throws {
        let raw = Data(0..<20)
        XCTAssertEqual(try TagDevice.decodeKey(raw.base64EncodedString(), advertisingID: nil), raw.prefix(16))
        XCTAssertEqual(try TagDevice.decodeKey("000102030405060708090a0b0c0d0e0f10111213", advertisingID: "abc"), raw.prefix(16))
        XCTAssertThrowsError(try TagDevice.decodeKey("abc", advertisingID: "x"))
        XCTAssertThrowsError(try TagDevice.decodeKey("AQID", advertisingID: nil))
    }
    func testCallbackOriginAndDuplicatesRejected() {
        XCTAssertThrowsError(try SamsungAuth.callbackFields(URL(string: "ms-app://wrong?code=x")!))
        XCTAssertThrowsError(try SamsungAuth.callbackFields(URL(string: "\(SamsungAuth.redirect)?code=x&code=y")!))
    }
    func testPaginationCannotLeakBearer() throws {
        let base = URL(string: "https://client.smartthings.com/devices")!
        XCTAssertEqual(try SamsungAuth.page("?page=2", relativeTo: base).host, base.host)
        XCTAssertThrowsError(try SamsungAuth.page("https://evil.test/devices", relativeTo: base))
        XCTAssertThrowsError(try SamsungAuth.page("http://client.smartthings.com/devices", relativeTo: base))
    }
    func testMalformedMetadataIsNotReady() {
        let device = TagDevice(json: ["deviceId":"fixture", "type":"BLE_D2D", "bleD2D":["encryptionKey":"", "cipher":"unsupported"]])
        XCTAssertNotNil(device)
        XCTAssertFalse(device!.metadataReady)
    }
    func testFormEscapesBase64PlusAndEquals() {
        XCTAssertEqual(String(data: SamsungAuth.form(["svcParam":"a+b/c=="]), encoding: .utf8), "svcParam=a%2Bb%2Fc%3D%3D")
        XCTAssertEqual(SamsungAuth.queryURL(URLComponents(string:"https://account.samsung.com/test?x=a+b")!)?.absoluteString, "https://account.samsung.com/test?x=a%2Bb")
    }
}
