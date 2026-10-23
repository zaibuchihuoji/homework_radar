import XCTest
import UIKit
@testable import Runner

final class WidgetDataTests: XCTestCase {
  func testBackgroundIntervalAndRetryPolicy() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    XCTAssertNil(BackgroundRefreshPolicy.nextDate(enabled: false, minutes: 30, retryAt: nil, now: now))
    XCTAssertEqual(BackgroundRefreshPolicy.nextDate(enabled: true, minutes: 30, retryAt: nil, now: now), now.addingTimeInterval(1800))
    XCTAssertEqual(BackgroundRefreshPolicy.nextDate(enabled: true, minutes: 30, retryAt: now.addingTimeInterval(300).timeIntervalSince1970 * 1000, now: now), now.addingTimeInterval(300))
  }
  func testBackgroundRunUsesExistingEngineAndPublishesVisibleCache() {
    let app = UIApplication.shared.delegate as! AppDelegate
    let identity = ObjectIdentifier(app.sharedEngine)
    let completed = expectation(description: "Shared-engine refresh")
    app.backgroundRefresh.run { success in
      XCTAssertTrue(success)
      XCTAssertEqual(ObjectIdentifier(app.sharedEngine), identity)
      XCTAssertNotNil(WidgetShared.defaults?.string(forKey: "homework_snapshot"))
      completed.fulfill()
    }
    wait(for: [completed], timeout: 30)
  }
  func testSelfSigningGroupResolution() {
    XCTAssertEqual(WidgetShared.groupID(info: ["ALTAppGroups": ["group.other", WidgetShared.baseGroup + ".TEST"]]), WidgetShared.baseGroup + ".TEST")
    XCTAssertEqual(WidgetShared.groupID(info: [:]), WidgetShared.baseGroup)
  }

  func testWidgetDateFilteringKeepsUndatedAndDoesNotResurrectPreviousSemester() {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23))!
    let old = Calendar.current.date(from: DateComponents(year: 2025, month: 5, day: 17))!
    let json: [String: Any] = ["items": [
      ["id": "old", "title": "旧作业", "d": old.timeIntervalSince1970 * 1000],
      ["id": "now", "title": "当前作业", "d": now.timeIntervalSince1970 * 1000],
      ["id": "undated", "title": "无截止"]]]
    XCTAssertEqual(WidgetData.homework(json, at: now).map(\.id), ["now", "undated"])
    let url = WidgetShared.url(timetable: false, id: "中文 / & ? # 📚")
    XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value, "中文 / & ? # 📚")
  }

  func testTimetableRecalculatesWeekAndIncludesUnknownWeeks() {
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!
    let second = Calendar.current.date(byAdding: .day, value: 7, to: start)!
    let json: [String: Any] = ["start": start.timeIntervalSince1970 * 1000, "days": ["1": [
      ["n": "单周", "w": [1], "s": "08:00", "e": "09:00"],
      ["n": "双周", "w": [2], "s": "09:00", "e": "10:00"],
      ["n": "未知周", "w": [], "s": "", "e": ""]]]]
    XCTAssertEqual(WidgetData.week(json, at: second), 2)
    XCTAssertEqual(WidgetData.lessons(json, at: second).map(\.title), ["双周", "未知周"])
  }
}
