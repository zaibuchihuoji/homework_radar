import Flutter
import UIKit
import XCTest
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

}
