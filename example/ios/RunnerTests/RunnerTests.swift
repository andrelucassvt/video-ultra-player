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

    // Each segment stacks the outline pass (behind) and the fill pass (front).
    let firstVariant = try XCTUnwrap(cueContainer.sublayers?.first)
    XCTAssertEqual(firstVariant.sublayers?.count, 2)

    // The container is already positioned at the caption center; both text
    // layers must use a container-local frame, or the absolute offset is
    // applied twice and the text is drawn off-canvas.
    let textLayers = try XCTUnwrap(firstVariant.sublayers)
    for textLayer in textLayers {
      XCTAssertEqual(textLayer.frame.origin, .zero)
      XCTAssertEqual(textLayer.frame.size, firstVariant.frame.size)
      XCTAssertNotNil(textLayer.animation(forKey: "captionVisibility"))
    }

    let outlineLayer = try XCTUnwrap(firstVariant.sublayers?.first as? CATextLayer)
    let outlineAttributed = try XCTUnwrap(outlineLayer.string as? NSAttributedString)
    XCTAssertEqual(
      outlineAttributed.attribute(.strokeColor, at: 0, effectiveRange: nil) as? UIColor,
      UIColor.black
    )
    XCTAssertGreaterThan(
      (outlineAttributed.attribute(.strokeWidth, at: 0, effectiveRange: nil) as? NSNumber)?
        .doubleValue ?? 0,
      0
    )

    let fillLayer = try XCTUnwrap(firstVariant.sublayers?[1] as? CATextLayer)
    let fillAttributed = try XCTUnwrap(fillLayer.string as? NSAttributedString)
    XCTAssertNil(fillAttributed.attribute(.strokeWidth, at: 0, effectiveRange: nil))
    XCTAssertEqual(
      fillAttributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor,
      UIColor(argb: 0xFFFFD700)
    )
    XCTAssertEqual(
      fillAttributed.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? UIColor,
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

    // Doubled to compensate the centered stroke: the fill pass covers the
    // inner half, leaving the visible outline at the preview's width.
    XCTAssertEqual(
      CaptionLayers.strokeWidthPercentage(for: style),
      10,
      accuracy: 0.000_001
    )
  }

  func testCaptionVisibilityKeyframesHaveOneMoreKeyTimeThanValues() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0.25,
      endFraction: 0.75
    )

    XCTAssertEqual(keyframes.keyTimes.count, keyframes.values.count + 1)
  }

  func testCaptionVisibilityKeyframesSpanTheFullRange() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0.25,
      endFraction: 0.75
    )

    XCTAssertEqual(keyframes.keyTimes.first?.doubleValue, 0)
    XCTAssertEqual(keyframes.keyTimes.last?.doubleValue, 1)
  }

  func testCaptionVisibilityKeyframesFadeInAndOutAroundTheWindow() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0.25,
      endFraction: 0.75
    )

    XCTAssertEqual(keyframes.values.map(\.doubleValue), [0, 1, 0])
    XCTAssertEqual(keyframes.keyTimes.map(\.doubleValue), [0, 0.25, 0.75, 1])
  }

  func testCaptionVisibilityKeyframesVisibleFromTheStart() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0,
      endFraction: 0.75
    )

    XCTAssertEqual(keyframes.values.map(\.doubleValue), [1, 0])
    XCTAssertEqual(keyframes.keyTimes.map(\.doubleValue), [0, 0.75, 1])
  }

  func testCaptionVisibilityKeyframesEndingAtVideoEndDoNotDuplicateKeyTime() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0.25,
      endFraction: 1
    )

    XCTAssertEqual(keyframes.values.map(\.doubleValue), [0, 1])
    XCTAssertEqual(keyframes.keyTimes.map(\.doubleValue), [0, 0.25, 1])
  }

  func testCaptionVisibilityKeyframesCoveringTheWholeVideo() {
    let keyframes = CaptionLayers.visibilityKeyframes(
      startFraction: 0,
      endFraction: 1
    )

    XCTAssertEqual(keyframes.values.map(\.doubleValue), [1])
    XCTAssertEqual(keyframes.keyTimes.map(\.doubleValue), [0, 1])
  }
}
