import Flutter
import UIKit
import XCTest
import MLKitVision
import MLKitTextRecognition
import MLKitTextRecognitionChinese
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
