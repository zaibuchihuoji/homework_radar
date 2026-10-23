import XCTest
import Flutter
import UIKit
@testable import Runner

final class IOSMajorFlowIntegrationDriver: XCTestCase {
  func testDartFlowsOnActualIOSRuntime() {
    let finished = expectation(description: "Flutter device integration suite")
    let app = UIApplication.shared.delegate as! AppDelegate
    let channel = FlutterMethodChannel(name: "homework_radar/ios_validation", binaryMessenger: app.sharedEngine.binaryMessenger)
    func poll() {
      channel.invokeMethod("results", arguments: nil) { value in
        if let results = value as? [String: String] {
          XCTAssertEqual(results.count, 4, "All four primary flows must report a result")
          for (name, result) in results { XCTAssertEqual(result, "success", "\(name): \(result)") }
          finished.fulfill()
        } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { poll() } }
      }
    }
    poll()
    wait(for: [finished], timeout: 240)
  }
}
