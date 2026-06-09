import Flutter
import XCTest

@testable import video_ultra_player

class RunnerTests: XCTestCase {
  func testUnknownMethodIsNotImplemented() {
    let plugin = VideoUltraPlayerPlugin()
    let call = FlutterMethodCall(methodName: "unknown", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue(result is FlutterMethodNotImplemented)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
