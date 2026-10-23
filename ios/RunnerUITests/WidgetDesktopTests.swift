import XCTest

final class WidgetDesktopTests: XCTestCase {
  func testAddHomeworkWidgetToHomeScreen() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    if alert.waitForExistence(timeout: 6) {
      let allow = alert.buttons["Allow"]
      if allow.exists { allow.tap() }
    }
    sleep(2)
    XCUIDevice.shared.press(.home)
    let icon = springboard.icons["作业通"].firstMatch
    XCTAssertTrue(icon.waitForExistence(timeout: 10), springboard.debugDescription)
    icon.press(forDuration: 1.5)
    let editHome = springboard.buttons["Edit Home Screen"]
    XCTAssertTrue(editHome.waitForExistence(timeout: 5), springboard.debugDescription)
    editHome.tap()
    let addButton = springboard.buttons["Add Widget"]
    if !addButton.exists {
      let edit = springboard.buttons["Edit"]
      if edit.exists { edit.tap() }
    }
    if addButton.exists { addButton.tap() }
    else {
      let plus = springboard.buttons["Add"]
      XCTAssertTrue(plus.waitForExistence(timeout: 5), springboard.debugDescription)
      plus.tap()
    }
    // SpringBoard also exposes an off-screen App Library search field.
    let search = springboard.searchFields["Search Widgets"]
    XCTAssertTrue(search.waitForExistence(timeout: 8), springboard.debugDescription)
    search.tap()
    search.typeText("作业通")
    let result = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "作业通")).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 10), springboard.debugDescription)
    result.tap()
    let addWidget = springboard.buttons["Add Widget"]
    XCTAssertTrue(addWidget.waitForExistence(timeout: 8), springboard.debugDescription)
    addWidget.tap()
    let done = springboard.buttons["Done"]
    if done.waitForExistence(timeout: 3) { done.tap() }
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.staticTexts["最近作业"].waitForExistence(timeout: 12), springboard.debugDescription)
    let attachment = XCTAttachment(screenshot: springboard.screenshot())
    attachment.name = "WidgetKit-home-screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
