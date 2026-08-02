import AVFoundation
import Flutter
import QuartzCore
import XCTest

@testable import video_ultra_player

class RunnerTests: XCTestCase {
  func testUnknownMethodIsNotImplemented() {
    let plugin = VideoUltraPlayerPlugin()
    let call = FlutterMethodCall(methodName: "unknown", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue((result as AnyObject) === FlutterMethodNotImplemented)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testTextExportUsesCATextLayerWithoutRasterContents() throws {
    let overlay = try XCTUnwrap(
      TextOverlayDescriptor(dictionary: [
        "id": "title",
        "text": "Export title",
        "startMs": 0,
        "endMs": 2_000,
        "x": 0.5,
        "y": 0.5,
        "fontSize": 0.08,
      ])
    )

    let parentLayer = TextOverlayLayers.makeTextOverlayParentLayer(
      overlays: [overlay],
      renderSize: CGSize(width: 1_080, height: 1_920),
      totalDuration: CMTime(seconds: 3, preferredTimescale: 600)
    )

    let textLayer = try XCTUnwrap(parentLayer.sublayers?.first as? CATextLayer)
    XCTAssertNil(textLayer.contents)
    XCTAssertNotNil(textLayer.animation(forKey: "timelineVisibility"))
  }

  func testTextOverlayTrackIsCompositedAboveVideoTrack() {
    let videoTrackID: CMPersistentTrackID = 101
    let overlayTrackID: CMPersistentTrackID = 202
    let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction()
    videoLayerInstruction.trackID = videoTrackID
    let compositionInstruction = AVMutableVideoCompositionInstruction()
    compositionInstruction.layerInstructions = [videoLayerInstruction]

    TextOverlayLayers.prependOverlayTrack(
      overlayTrackID,
      to: [compositionInstruction]
    )

    XCTAssertEqual(
      compositionInstruction.layerInstructions.map(\.trackID),
      [overlayTrackID, videoTrackID]
    )
  }
}
