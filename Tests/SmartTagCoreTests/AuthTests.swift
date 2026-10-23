import XCTest
@testable import SmartTagCore

final class AuthTests: XCTestCase {
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
