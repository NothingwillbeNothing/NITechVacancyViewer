import XCTest

final class DemoUITests: XCTestCase {
    func testDemoNavigationAndSignOut() {
        let app = XCUIApplication()
        app.launch()
        let demo = app.buttons["demoButton"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        XCTAssertTrue(app.navigationBars["NITechSearch"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS-demo-home"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.tabBars.buttons["今日の予約"].tap()
        XCTAssertTrue(app.navigationBars["今日の予約"].waitForExistence(timeout: 5))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.buttons["デモを終了"].tap()
        let logout = app.buttons["ログアウト"].firstMatch
        XCTAssertTrue(logout.waitForExistence(timeout: 5))
        logout.tap()
        XCTAssertTrue(app.buttons["demoButton"].waitForExistence(timeout: 5))
    }
}
