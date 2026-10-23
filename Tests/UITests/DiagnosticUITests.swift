import XCTest

final class DiagnosticUITests: XCTestCase {
    func testFreshInstallShowsLoginAndNoBatteryResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["Iniciar sesión con Samsung"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["batteryResult"].exists)
    }

    func testEventScreenCanBeOpenedWithoutSigningIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["Registro técnico"].tap()
        XCTAssertTrue(app.staticTexts["Sin eventos"].exists)
    }
}
