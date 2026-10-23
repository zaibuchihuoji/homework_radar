import XCTest

final class WidgetDesktopTests: XCTestCase {
  func testAddHomeworkWidgetToHomeScreen() throws {
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
    XCTAssertTrue(springboard.searchFields["Search Widgets"].waitForExistence(timeout: 8), springboard.debugDescription)
    // The headless simulator gallery search does not acquire keyboard focus.
    // Exercise the normal list route instead of depending on system text input.
    let result = springboard.staticTexts["作业通"].firstMatch
    for _ in 0..<10 {
      if result.exists && result.isHittable { break }
      springboard.swipeUp()
    }
    XCTAssertTrue(result.exists && result.isHittable, springboard.debugDescription)
    result.tap()
    let addWidget = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Add Widget")).firstMatch
    XCTAssertTrue(addWidget.waitForExistence(timeout: 8), springboard.debugDescription)
    addWidget.tap()
    let done = springboard.buttons["Done"]
    if done.waitForExistence(timeout: 3) { done.tap() }
    let widgetElements = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "最近作业"))
    XCTAssertTrue(widgetElements.firstMatch.waitForExistence(timeout: 12), springboard.debugDescription)
    let widget = try XCTUnwrap(widgetElements.allElementsBoundByIndex.first(where: { $0.isHittable }), springboard.debugDescription)
    let screenshot = springboard.screenshot()
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try screenshot.pngRepresentation.write(to: documents.appendingPathComponent("widget-desktop.png"))
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "WidgetKit-home-screen"
    attachment.lifetime = .keepAlways
    add(attachment)
    widget.tap()
    let open = springboard.alerts.buttons["Open"]
    if open.waitForExistence(timeout: 2) { open.tap() }
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
  }
}
