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

  func testKaraokeCaptionExportUsesOneFullTextVariantAtATime() throws {
    let cue = try XCTUnwrap(
      CaptionCueDescriptor(dictionary: [
        "text": "hello world",
        "startMs": 0,
        "endMs": 2_000,
        "words": [
          ["text": "hello", "startMs": 0, "endMs": 1_000],
          ["text": "world", "startMs": 1_000, "endMs": 2_000],
        ],
      ])
    )
    let style = try XCTUnwrap(
      CaptionStyleDescriptor(dictionary: [
        "color": 0xFFFFFFFF,
        "highlightColor": 0xFFFFD700,
        "fontSize": 0.06,
        "strokeWidth": 0.003,
        "karaoke": true,
      ])
    )

    let segments = CaptionLayers.presentationSegments(
      for: cue,
      style: style,
      totalSeconds: 2
    )
    XCTAssertEqual(
      segments,
      [
        CaptionPresentationSegment(
          startSeconds: 0,
          endSeconds: 1,
          highlightedWordIndex: 0
        ),
        CaptionPresentationSegment(
          startSeconds: 1,
          endSeconds: 2,
          highlightedWordIndex: 1
        ),
      ]
    )

    let parent = CaptionLayers.makeCaptionParentLayer(
      cues: [cue],
      style: style,
      renderSize: CGSize(width: 1_080, height: 1_920),
      totalDuration: CMTime(seconds: 2, preferredTimescale: 600)
    )
    let cueContainer = try XCTUnwrap(parent.sublayers?.first)
    XCTAssertEqual(cueContainer.sublayers?.count, 2)

    let firstVariant = try XCTUnwrap(cueContainer.sublayers?.first as? CATextLayer)
    let attributed = try XCTUnwrap(firstVariant.string as? NSAttributedString)
    XCTAssertEqual(
      attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
      UIColor(argb: 0xFFFFD700)
    )
    XCTAssertEqual(
      attributed.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? UIColor,
      UIColor(argb: 0xFFFFFFFF)
    )
  }

  func testKaraokeCaptionKeepsBaseTextVisibleBetweenWordsWithoutOverlap() throws {
    let cue = try XCTUnwrap(
      CaptionCueDescriptor(dictionary: [
        "text": "hello world",
        "startMs": 0,
        "endMs": 3_000,
        "words": [
          ["text": "hello", "startMs": 500, "endMs": 1_200],
          ["text": "world", "startMs": 1_500, "endMs": 2_200],
        ],
      ])
    )
    let style = try XCTUnwrap(
      CaptionStyleDescriptor(dictionary: ["karaoke": true])
    )

    let segments = CaptionLayers.presentationSegments(
      for: cue,
      style: style,
      totalSeconds: 3
    )

    XCTAssertEqual(segments.count, 5)
    XCTAssertEqual(segments.map(\.highlightedWordIndex), [nil, 0, nil, 1, nil])
    for (current, next) in zip(segments, segments.dropFirst()) {
      XCTAssertEqual(current.endSeconds, next.startSeconds, accuracy: 0.000_001)
    }
  }

  func testCaptionStrokeConvertsVideoFractionToFontPercentage() throws {
    let style = try XCTUnwrap(
      CaptionStyleDescriptor(dictionary: [
        "fontSize": 0.06,
        "strokeWidth": 0.003,
      ])
    )

    XCTAssertEqual(
      CaptionLayers.strokeWidthPercentage(for: style),
      -5,
      accuracy: 0.000_001
    )
  }
}
