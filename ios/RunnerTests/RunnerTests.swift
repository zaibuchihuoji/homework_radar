import Flutter
import UIKit
import XCTest
import MLKitVision
import MLKitTextRecognition
import MLKitTextRecognitionChinese
import UserNotifications
@testable import Runner

class RunnerTests: XCTestCase {

  func testKeychainRoundTripAndDelete() throws {
    let key = "test-" + UUID().uuidString
    defer { SecureBox.delete(key) }
    XCTAssertTrue(SecureBox.write(key, "synthetic-test-value"))
    XCTAssertEqual(try SecureBox.read(key), "synthetic-test-value")
    XCTAssertTrue(SecureBox.write(key, "replacement-test-value"))
    XCTAssertEqual(try SecureBox.read(key), "replacement-test-value")
    SecureBox.delete(key)
    XCTAssertNil(try SecureBox.read(key))
  }

  func testBundledChineseRecognizerReadsHomeworkScreenshot() {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 220)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 900, height: 220))
      ("计算机网络 作业" as NSString).draw(at: CGPoint(x: 35, y: 65), withAttributes: [
        .font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black,
      ])
    }
    let completed = expectation(description: "Chinese OCR completed")
    let recognizer = TextRecognizer.textRecognizer(options: ChineseTextRecognizerOptions())
    recognizer.process(VisionImage(image: image)) { text, error in
      XCTAssertNil(error)
      XCTAssertTrue(text?.text.contains("计算机网络") == true, text?.text ?? "No recognition result")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 30)
  }

}

/// Run after MajorFlowsTests, against that same disposable simulator container.
final class MajorFlowsPersistenceTests: XCTestCase {
  func testStoredRecordsAndPendingNativeRemindersAgree() throws {
    let raw = try XCTUnwrap(UserDefaults.standard.string(forKey: "flutter.homework_json"))
    let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
    XCTAssertEqual(rows.first(where: { $0["title"] as? String == "QA old keep" })?["note"] as? String, "keep-note")
    XCTAssertFalse(rows.contains(where: { ($0["title"] as? String ?? "").hasPrefix("QA task") }))
    let ocr = try XCTUnwrap(rows.first(where: { $0["title"] as? String == "QA OCR reading" }))
    XCTAssertEqual(ocr["course"] as? String, "QA English")
    XCTAssertNotNil(ocr["dueAt"] as? Double)
    XCTAssertTrue((ocr["note"] as? String ?? "").contains("第四单元"))
    let completed = expectation(description: "Native pending reminders")
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let byID = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, [String: Any])? in
        guard let id = row["id"] as? String else { return nil }
        return (id, row)
      })
      XCTAssertFalse(requests.isEmpty, "Future OCR homework must retain its reminders")
      for request in requests {
        let id = request.content.userInfo["payload"] as? String ?? ""
        let row = byID[id]
        XCTAssertNotNil(row, "No notification may point at deleted/missing homework")
        if let due = row?["dueAt"] as? Double,
           let fire = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() {
          let hours = (due / 1000 - fire.timeIntervalSince1970) / 3600
          XCTAssertTrue([1.0, 6.0, 24.0].contains(where: { abs($0 - hours) < 0.001 }), "Deadline timezone or trigger mismatch: \(hours)")
        } else { XCTFail("Missing native calendar trigger or deadline") }
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 15)
  }
}
