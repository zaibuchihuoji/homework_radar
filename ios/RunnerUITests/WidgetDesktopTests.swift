import XCTest
import UIKit

/// Runs only in the disposable CI simulator. It uses the shipping app, real
/// platform views, Photos picker, OCR plugin, storage and local notifications.
final class MajorFlowsTests: XCTestCase {
  private let app = XCUIApplication()
  private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  override func setUpWithError() throws {
    continueAfterFailure = false
    app.launch()
    allowNotifications()
    XCTAssertTrue(element(containing: "作业标签页").waitForExistence(timeout: 20), app.debugDescription)
  }

  override func tearDownWithError() throws {
    capture(name + "-final")
  }

  private func element(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + "\n")).firstMatch
  }

  private func element(containing text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  private func tap(_ label: String, scroll: Bool = false) {
    let target = element(label)
    if scroll {
      for _ in 0..<8 {
        if target.exists && target.isHittable { break }
        app.swipeUp()
      }
    }
    XCTAssertTrue(target.waitForExistence(timeout: 8) && target.isHittable, "Missing \(label)\n\(app.debugDescription)")
    target.tap()
  }

  private func tab(_ label: String) {
    let target = element(containing: label + "标签页")
    XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
    target.tap()
  }

  private func back() {
    let target = app.buttons.matching(NSPredicate(format: "label == '返回' OR label == 'Back'")).firstMatch
    XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
    target.tap()
  }

  private func allowNotifications() {
    let alert = springboard.alerts.firstMatch
    if alert.waitForExistence(timeout: 6) {
      let allow = alert.buttons.matching(NSPredicate(format: "label == 'Allow' OR label == '允许'")).firstMatch
      if allow.exists { allow.tap() }
    }
  }

  private func capture(_ filename: String) {
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("major-flows")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let safe = filename.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    try? app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(safe + ".png"))
    try? app.debugDescription.write(to: directory.appendingPathComponent(safe + ".txt"), atomically: true, encoding: .utf8)
  }

  private func replace(_ field: XCUIElement, with text: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
    field.tap()
    let keyboardIntro = app.buttons["Continue"]
    if keyboardIntro.exists && keyboardIntro.isHittable { keyboardIntro.tap() }
    let old = field.value as? String ?? ""
    if !old.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
    field.typeText(text)
  }

  private func finishTyping() {
    let done = app.keyboards.buttons.matching(NSPredicate(format: "label == 'Done' OR label == '完成' OR label == 'done'")).firstMatch
    if done.exists { done.tap() }
  }

  private func createManual(_ title: String, note: String) {
    tap("添加作业")
    tap("手动添加")
    // Flutter's iOS accessibility bridge exposes multiline fields as TextField.
    replace(app.textFields.element(boundBy: 0), with: "QA Course")
    replace(app.textFields.element(boundBy: 2), with: note)
    replace(app.textFields.element(boundBy: 1), with: title)
    finishTyping()
    tap("添加", scroll: true)
    XCTAssertTrue(element(containing: title).waitForExistence(timeout: 8), app.debugDescription)
  }

  private func menu(_ title: String, action: String) {
    let item = element(containing: title)
    XCTAssertTrue(item.waitForExistence(timeout: 8), app.debugDescription)
    item.press(forDuration: 1.1)
    tap(action)
  }

  func test01ManualCreateEditHideRestoreDeleteAndRelaunch() throws {
    createManual("QA old keep", note: "keep-note")
    createManual("QA task", note: "initial-note")
    menu("QA task", action: "编辑作业")
    replace(app.textFields.element(boundBy: 2), with: "changed-note")
    replace(app.textFields.element(boundBy: 1), with: "QA task edited")
    finishTyping()
    tap("保存", scroll: true)
    XCTAssertTrue(element(containing: "QA task edited").waitForExistence(timeout: 8))
    capture("01-edited")
    app.terminate()
    app.launch()
    XCTAssertTrue(element(containing: "QA task edited").waitForExistence(timeout: 15))
    XCTAssertTrue(element(containing: "QA old keep").exists)
    menu("QA task edited", action: "标记完成")
    tap("已完成")
    XCTAssertTrue(element(containing: "QA task edited").waitForExistence(timeout: 5))
    menu("QA task edited", action: "标记未完成")
    tap("未完成")
    menu("QA task edited", action: "隐藏这条作业")
    tab("设置")
    tap("已隐藏的作业", scroll: true)
    XCTAssertTrue(element(containing: "QA task edited").waitForExistence(timeout: 5))
    tap("恢复")
    back()
    tab("作业")
    XCTAssertTrue(element(containing: "QA task edited").waitForExistence(timeout: 5))
    menu("QA task edited", action: "删除")
    tap("取消")
    XCTAssertTrue(element(containing: "QA task edited").exists)
    menu("QA task edited", action: "删除")
    tap("删除")
    sleep(1)
    app.terminate()
    app.launch()
    XCTAssertTrue(element(containing: "QA old keep").waitForExistence(timeout: 15))
    XCTAssertFalse(element(containing: "QA task edited").exists)
    capture("01-persisted-delete-and-old-record")
  }

  func test02PhotosScreenshotOcrReviewAndConfirm() throws {
    tap("添加作业")
    tap("识别添加")
    tap("选择截图")
    // PHPicker also has a grid Other whose label starts with every photo name.
    // Select the actual Image, never that non-hittable grouping element.
    let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH '照片' OR label == 'Photo'")).firstMatch
    if photo.waitForExistence(timeout: 10) && photo.isHittable {
      photo.tap()
    } else {
      let cell = app.collectionViews.cells.firstMatch
      XCTAssertTrue(cell.waitForExistence(timeout: 5), app.debugDescription)
      cell.tap()
    }
    XCTAssertTrue(element("核对识别结果").waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(element(containing: "检查并添加（2）").exists, app.debugDescription)
    capture("02-real-ocr-review")
    let title = app.textFields.matching(NSPredicate(format: "value CONTAINS '第四单元'")).firstMatch
    replace(title, with: "QA OCR reading")
    // The course field is single-line; Done dismisses the system keyboard.
    replace(app.textFields.firstMatch, with: "QA English")
    finishTyping()
    tap("检查并添加（2）")
    XCTAssertTrue(element("确认添加作业").waitForExistence(timeout: 5))
    capture("02-final-confirmation")
    tap("确认添加 2 项")
    XCTAssertTrue(element(containing: "QA OCR reading").waitForExistence(timeout: 10), app.debugDescription)
    capture("02-saved")
  }

  func test03OfficialLoginPagesAndUnauthenticatedDetection() throws {
    for (index, platform) in ["学习通", "中国大学MOOC", "智慧树", "学堂在线", "雨课堂"].enumerated() {
      // Each iteration starts from the actual app shell, without test cookies.
      if index > 0 { app.terminate(); app.launch() }
      XCTAssertTrue(element(containing: "账号标签页").waitForExistence(timeout: 15))
      tab("账号")
      let heading = element(platform)
      var login: XCUIElement?
      for _ in 0..<10 {
        if heading.exists && heading.isHittable && heading.frame.height >= 100 {
          let buttons = app.buttons.matching(NSPredicate(format: "label == '登录'")).allElementsBoundByIndex
          login = buttons.filter {
            $0.isHittable && $0.frame.minY > heading.frame.minY &&
            $0.frame.maxY <= heading.frame.maxY
          }.min { $0.frame.minY < $1.frame.minY }
          if login != nil { break }
        }
        app.swipeUp()
      }
      try XCTUnwrap(login, app.debugDescription).tap()
      XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
      sleep(5)
      capture("03-\(index)-official-login")
      tap("检测")
      XCTAssertTrue(element(containing: "未检测到登录态").waitForExistence(timeout: 15), app.debugDescription)
      capture("03-\(index)-not-logged-in")
      back()
    }
  }

  func test04ScheduledReminderDeliveredAndOpensDetail() throws {
    tap("添加作业")
    tap("识别添加")
    let format = DateFormatter()
    // Match the simulator's system timezone, as the app's date editor does.
    format.timeZone = .current
    format.dateFormat = "yyyy-MM-dd HH:mm"
    let due = Date().addingTimeInterval(3600 + 120)
    let text = "【QA Notify】QA reminder 作业，截止" + format.string(from: due)
    let input = app.textFields["作业通知"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    replace(input, with: text)
    tap("识别作业", scroll: true)
    XCTAssertTrue(element(containing: "检查并添加（1）").waitForExistence(timeout: 8), app.debugDescription)
    tap("检查并添加（1）")
    tap("确认添加 1 项")
    XCTAssertTrue(element(containing: "QA reminder").waitForExistence(timeout: 8))
    capture("04-reminder-scheduled")
    XCUIDevice.shared.press(.home)
    // Exercise the important cold-start path: the local notification must be
    // delivered with the process stopped, then open that exact homework.
    app.terminate()
    let delivered = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'QA reminder' OR label CONTAINS '作业即将截止：QA Notify'")).firstMatch
    XCTAssertTrue(delivered.waitForExistence(timeout: 150), springboard.debugDescription)
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("major-flows")
    try springboard.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("04-native-notification.png"))
    delivered.tap()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    XCTAssertTrue(element("截止时间").waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(element(containing: "QA reminder").exists)
    capture("04-notification-opened-detail")
  }
}

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
