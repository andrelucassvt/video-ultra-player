import AVFoundation
import CoreText
import UIKit

/// A single word of a caption cue with its own presentation window, used by
/// the karaoke highlight mode.
struct CaptionWordDescriptor {
  let text: String
  let startMs: Int64
  let endMs: Int64

  init?(dictionary: [String: Any]) {
    guard let text = dictionary["text"] as? String else {
      return nil
    }
    self.text = text
    self.startMs = (dictionary["startMs"] as? NSNumber)?.int64Value ?? 0
    self.endMs = (dictionary["endMs"] as? NSNumber)?.int64Value ?? 0
  }
}

/// One caption cue visible on the timeline during `[startMs, endMs)`.
///
/// `words` carries the per-word windows used by the karaoke style; it is
/// never nil (the Dart side serialises an empty list when no words exist).
struct CaptionCueDescriptor {
  let text: String
  let startMs: Int64
  let endMs: Int64
  let words: [CaptionWordDescriptor]

  init?(dictionary: [String: Any]) {
    guard let text = dictionary["text"] as? String else {
      return nil
    }
    self.text = text
    self.startMs = (dictionary["startMs"] as? NSNumber)?.int64Value ?? 0
    self.endMs = (dictionary["endMs"] as? NSNumber)?.int64Value ?? 0
    let rawWords = dictionary["words"] as? [[String: Any]] ?? []
    self.words = rawWords.compactMap(CaptionWordDescriptor.init(dictionary:))
  }
}

/// Visual style applied to every caption cue. Colors are ARGB `UInt32` values
/// from the method channel; `fontSize` and `strokeWidth` are fractions of the
/// video height; `positionY` is the center of the caption block in normalized
/// frame coordinates (`0.0` top edge, `1.0` bottom edge).
struct CaptionStyleDescriptor {
  let color: UInt32
  let fontSize: CGFloat
  let positionY: CGFloat
  let uppercase: Bool
  let karaoke: Bool
  let strokeWidth: CGFloat
  let backgroundOpacity: CGFloat
  let highlightColor: UInt32

  init?(dictionary: [String: Any]) {
    self.color = (dictionary["color"] as? NSNumber)?.uint32Value ?? 0xFFFFFFFF
    self.fontSize = CGFloat(
      min(max((dictionary["fontSize"] as? NSNumber)?.doubleValue ?? 0.055, 0.01), 1)
    )
    self.positionY = CGFloat(
      min(max((dictionary["positionY"] as? NSNumber)?.doubleValue ?? 0.85, 0), 1)
    )
    self.uppercase = dictionary["uppercase"] as? Bool ?? false
    self.karaoke = dictionary["karaoke"] as? Bool ?? false
    self.strokeWidth = CGFloat(
      max((dictionary["strokeWidth"] as? NSNumber)?.doubleValue ?? 0, 0)
    )
    self.backgroundOpacity = CGFloat(
      min(max((dictionary["backgroundOpacity"] as? NSNumber)?.doubleValue ?? 0, 0), 1)
    )
    self.highlightColor = (dictionary["highlightColor"] as? NSNumber)?.uint32Value ?? 0xFFFFD700
  }
}

/// A disjoint visual state for one caption cue.
///
/// Karaoke captions use one full-text variant at a time: either the base text
/// or the text with exactly one highlighted word. Keeping these windows
/// disjoint prevents Core Animation from compositing duplicate glyphs.
struct CaptionPresentationSegment: Equatable {
  let startSeconds: Double
  let endSeconds: Double
  let highlightedWordIndex: Int?
}

/// Builds the CALayer tree that burns captions into the exported MP4 and the
/// raster images used by the iOS preview, mirroring `TextOverlayLayers`.
enum CaptionLayers {
  /// Root layer for all caption cues, sized to the render frame.
  ///
  /// `isGeometryFlipped = true` gives top-left origin coordinates, matching
  /// the normalized `positionY` values coming from the Dart model.
  static func makeCaptionParentLayer(
    cues: [CaptionCueDescriptor],
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalDuration: CMTime
  ) -> CALayer {
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.isGeometryFlipped = true

    let totalSeconds = totalDuration.isNumeric
      ? max(CMTimeGetSeconds(totalDuration), 0)
      : 0
    guard totalSeconds > 0 else { return parentLayer }

    for cue in cues {
      guard let cueLayer = makeExportCueLayer(
        cue: cue,
        style: style,
        renderSize: renderSize,
        totalSeconds: totalSeconds
      ) else {
        continue
      }
      parentLayer.addSublayer(cueLayer)
    }
    return parentLayer
  }

  /// Rasterizes captions once per committed state so preview can draw the
  /// cached images into the texture pixel buffer without text layout per
  /// frame. In karaoke mode the cue is split into disjoint presentation
  /// segments: base text in gaps and one highlighted-word variant at a time.
  static func makeCaptionRasters(
    cues: [CaptionCueDescriptor],
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalDuration: CMTime
  ) -> [CaptionRaster] {
    let totalSeconds = totalDuration.isNumeric
      ? max(CMTimeGetSeconds(totalDuration), 0)
      : 0
    guard totalSeconds > 0 else { return [] }

    return cues.flatMap { cue -> [CaptionRaster] in
      makeCueRasters(
        cue: cue,
        style: style,
        renderSize: renderSize,
        totalSeconds: totalSeconds
      )
    }
  }

  // MARK: - Preview rasters

  private static func makeCueRasters(
    cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> [CaptionRaster] {
    let text = displayText(cue.text, style: style)
    return presentationSegments(
      for: cue,
      style: style,
      totalSeconds: totalSeconds
    ).compactMap { segment in
      let range = segment.highlightedWordIndex.map {
        highlightRange(for: $0, in: cue, style: style)
      }
      return makeRaster(
        text: text,
        highlightRange: range,
        cue: cue,
        style: style,
        renderSize: renderSize,
        startSeconds: segment.startSeconds,
        endSeconds: segment.endSeconds
      )
    }
  }

  private static func makeRaster(
    text: String,
    highlightRange: NSRange?,
    cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    startSeconds: Double,
    endSeconds: Double
  ) -> CaptionRaster? {
    let fontSize = style.fontSize * renderSize.height
    let font = UIFont.systemFont(ofSize: max(fontSize, 1), weight: .bold)
    let fillAttributed = fillAttributedText(
      text: text,
      font: font,
      style: style,
      highlightRange: highlightRange
    )

    let boundingRect = fillAttributed.boundingRect(
      with: CGSize(width: renderSize.width * 0.92, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let padding: CGFloat = fontSize * 0.3
    let boxSize = CGSize(
      width: max(ceil(boundingRect.width) + padding * 2, fontSize),
      height: max(ceil(boundingRect.height) + padding * 2, fontSize)
    )
    let center = CGPoint(
      x: renderSize.width / 2,
      y: style.positionY * renderSize.height
    )

    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: boxSize, format: format)
    let image = renderer.image { context in
      context.cgContext.clear(CGRect(origin: .zero, size: boxSize))
      if style.backgroundOpacity > 0 {
        UIColor.black.withAlphaComponent(style.backgroundOpacity).setFill()
        context.cgContext.fill(CGRect(origin: .zero, size: boxSize))
      }
      let drawRect = CGRect(
        x: padding - boundingRect.minX,
        y: padding - boundingRect.minY,
        width: max(boundingRect.width, fontSize),
        height: max(boundingRect.height, fontSize)
      )
      // Two passes like the Android renderer and the Flutter preview: the
      // outline (positive stroke, outline only) first, the fill on top so the
      // inner half of the centered stroke stays covered.
      if style.strokeWidth > 0 {
        outlineAttributedText(text: text, font: font, style: style).draw(
          with: drawRect,
          options: [.usesLineFragmentOrigin, .usesFontLeading],
          context: nil
        )
      }
      fillAttributed.draw(
        with: drawRect,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )
    }
    guard let cgImage = image.cgImage else { return nil }

    return CaptionRaster(
      image: cgImage,
      size: boxSize,
      center: center,
      startSeconds: startSeconds,
      endSeconds: endSeconds
    )
  }

  // MARK: - Export layers

  /// Uses CATextLayer for offline export, mirroring `TextOverlayLayers`.
  /// One layer per mutually exclusive caption state with a discrete opacity
  /// animation on `[start, end)`. Karaoke variants replace the base text
  /// instead of being composited on top of it.
  private static func makeExportCueLayer(
    cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> CALayer? {
    let text = displayText(cue.text, style: style)
    let container = CALayer()
    container.frame = CGRect(origin: .zero, size: renderSize)

    let segments = presentationSegments(
      for: cue,
      style: style,
      totalSeconds: totalSeconds
    )
    guard !segments.isEmpty else { return nil }

    for segment in segments {
      let range = segment.highlightedWordIndex.map {
        highlightRange(for: $0, in: cue, style: style)
      }
      guard let layer = makeExportTextLayer(
        text: text,
        highlightRange: range,
        style: style,
        renderSize: renderSize,
        totalSeconds: totalSeconds,
        startSeconds: segment.startSeconds,
        endSeconds: segment.endSeconds
      ) else {
        continue
      }
      container.addSublayer(layer)
    }
    return container
  }

  private static func makeExportTextLayer(
    text: String,
    highlightRange: NSRange?,
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalSeconds: Double,
    startSeconds: Double,
    endSeconds: Double
  ) -> CALayer? {
    let fontSize = style.fontSize * renderSize.height
    let font = UIFont.systemFont(ofSize: max(fontSize, 1), weight: .bold)
    let fillAttributed = fillAttributedText(
      text: text,
      font: font,
      style: style,
      highlightRange: highlightRange
    )

    let boundingRect = fillAttributed.boundingRect(
      with: CGSize(width: renderSize.width * 0.92, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let padding: CGFloat = fontSize * 0.3
    let boxSize = CGSize(
      width: max(ceil(boundingRect.width) + padding * 2, fontSize),
      height: max(ceil(boundingRect.height) + padding * 2, fontSize)
    )
    let center = CGPoint(
      x: renderSize.width / 2,
      y: style.positionY * renderSize.height
    )
    let frame = CGRect(
      x: center.x - boxSize.width / 2,
      y: center.y - boxSize.height / 2,
      width: boxSize.width,
      height: boxSize.height
    )

    let background = style.backgroundOpacity > 0
      ? UIColor.black.withAlphaComponent(style.backgroundOpacity).cgColor
      : nil
    let container = CALayer()
    container.frame = frame
    // The background lives on the container (applied once, behind both
    // passes) instead of on each text layer, where stacking would double
    // the semi-transparent box.
    container.backgroundColor = background
    // The container is already positioned at the caption center; the text
    // layers must use a container-local frame (origin .zero), otherwise the
    // absolute center offset is applied twice and the text is drawn off-canvas.
    let textFrame = CGRect(origin: .zero, size: boxSize)
    // Two passes per segment, mirroring the Android renderer: the outline
    // (positive stroke, outline only) behind the fill so the inner half of
    // the centered stroke stays covered and the highlight stays visible.
    if style.strokeWidth > 0 {
      container.addSublayer(
        makeCaptionTextLayer(
          string: outlineAttributedText(text: text, font: font, style: style),
          frame: textFrame,
          background: nil
        )
      )
    }
    container.addSublayer(
      makeCaptionTextLayer(
        string: fillAttributed,
        frame: textFrame,
        background: nil
      )
    )

    // CoreAnimationTool is an offline renderer. A discrete opacity animation
    // is reliable at both edges of [start, end), unlike CALayer timing fields
    // whose fill behavior can leak the model-layer opacity outside the window.
    let visibility = makeVisibilityAnimation(
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      totalSeconds: totalSeconds
    )
    container.sublayers?.forEach { sublayer in
      sublayer.add(visibility, forKey: "captionVisibility")
    }

    return container
  }

  private static func makeCaptionTextLayer(
    string: NSAttributedString,
    frame: CGRect,
    background: CGColor?
  ) -> CATextLayer {
    let layer = CATextLayer()
    layer.string = string
    layer.isWrapped = true
    layer.alignmentMode = .center
    layer.contentsScale = UIScreen.main.scale
    layer.allowsEdgeAntialiasing = true
    layer.frame = frame
    layer.opacity = 0
    if let background {
      layer.backgroundColor = background
    }
    return layer
  }

  /// Discrete opacity keyframes over the full video duration keeping the
  /// layer visible only during the half-open window `[start, end)`.
  private static func makeVisibilityAnimation(
    startSeconds: Double,
    endSeconds: Double,
    totalSeconds: Double
  ) -> CAKeyframeAnimation {
    let keyframes = visibilityKeyframes(
      startFraction: startSeconds / totalSeconds,
      endFraction: endSeconds / totalSeconds
    )
    let visibility = CAKeyframeAnimation(keyPath: "opacity")
    visibility.values = keyframes.values
    visibility.keyTimes = keyframes.keyTimes
    visibility.calculationMode = .discrete
    visibility.beginTime = AVCoreAnimationBeginTimeAtZero
    visibility.duration = totalSeconds
    visibility.fillMode = .both
    visibility.isRemovedOnCompletion = false
    return visibility
  }

  // MARK: - Shared helpers

  /// Builds a valid discrete keyframe sequence that keeps the layer visible
  /// only during the half-open window `[startFraction, endFraction)` of the
  /// full video duration.
  ///
  /// Core Animation requires `keyTimes.count == values.count + 1`, with the
  /// first keyTime at `0` and the last at `1`; an invalid sequence degrades
  /// to linear interpolation, which fades every cue in from the video start.
  /// When the window touches an edge the redundant segment is dropped so no
  /// keyTime is duplicated.
  static func visibilityKeyframes(
    startFraction: Double,
    endFraction: Double
  ) -> (values: [NSNumber], keyTimes: [NSNumber]) {
    let start = min(max(startFraction, 0), 1)
    let end = min(max(endFraction, 0), 1)
    if start <= 0 {
      if end >= 1 {
        return (values: [1], keyTimes: [0, 1])
      }
      return (values: [1, 0], keyTimes: [0, NSNumber(value: end), 1])
    }
    if end >= 1 {
      return (values: [0, 1], keyTimes: [0, NSNumber(value: start), 1])
    }
    return (
      values: [0, 1, 0],
      keyTimes: [0, NSNumber(value: start), NSNumber(value: end), 1]
    )
  }

  private static func displayText(_ text: String, style: CaptionStyleDescriptor) -> String {
    return style.uppercase ? text.uppercased() : text
  }

  /// The outline pass: a positive stroke width renders only the stroke, in
  /// black and centered on the glyph edge. The fill pass covers the inner
  /// half, so the stroke width is doubled (see [strokeWidthPercentage]) to
  /// keep the visible outline matching the Flutter preview's shadow.
  private static func outlineAttributedText(
    text: String,
    font: UIFont,
    style: CaptionStyleDescriptor
  ) -> NSAttributedString {
    var attributes = baseAttributes(font: font, style: style)
    if style.strokeWidth > 0 {
      attributes[.strokeColor] = UIColor.black
      attributes[.strokeWidth] = strokeWidthPercentage(for: style)
    }
    return NSAttributedString(string: text, attributes: attributes)
  }

  /// The fill pass: no stroke, the caption color with the karaoke highlight
  /// word overlaid.
  private static func fillAttributedText(
    text: String,
    font: UIFont,
    style: CaptionStyleDescriptor,
    highlightRange: NSRange?
  ) -> NSAttributedString {
    var attributes = baseAttributes(font: font, style: style)
    attributes[.foregroundColor] = UIColor(argb: style.color)
    let result = NSMutableAttributedString(string: text, attributes: attributes)
    if let range = highlightRange,
       range.location != NSNotFound,
       range.location + range.length <= (text as NSString).length {
      result.addAttribute(
        .foregroundColor,
        value: UIColor(argb: style.highlightColor),
        range: range
      )
    }
    return result
  }

  /// Attributes shared by both passes so the two layers lay out identically.
  private static func baseAttributes(
    font: UIFont,
    style: CaptionStyleDescriptor
  ) -> [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    return [
      .font: font,
      .paragraphStyle: paragraph,
    ]
  }

  static func presentationSegments(
    for cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor,
    totalSeconds: Double
  ) -> [CaptionPresentationSegment] {
    let cueStart = max(Double(cue.startMs) / 1_000, 0)
    let cueEnd = min(Double(cue.endMs) / 1_000, max(totalSeconds, 0))
    guard cueEnd > cueStart else { return [] }
    guard style.karaoke, !cue.words.isEmpty else {
      return [
        CaptionPresentationSegment(
          startSeconds: cueStart,
          endSeconds: cueEnd,
          highlightedWordIndex: nil
        ),
      ]
    }

    let wordWindows = cue.words.enumerated().compactMap { index, word
      -> (index: Int, start: Double, end: Double)? in
      let start = max(Double(word.startMs) / 1_000, cueStart)
      let end = min(Double(word.endMs) / 1_000, cueEnd)
      guard end > start else { return nil }
      return (index, start, end)
    }.sorted {
      $0.start == $1.start ? $0.index < $1.index : $0.start < $1.start
    }

    var segments: [CaptionPresentationSegment] = []
    var cursor = cueStart
    for window in wordWindows where cursor < cueEnd {
      let activeStart = max(window.start, cursor)
      if activeStart > cursor {
        segments.append(
          CaptionPresentationSegment(
            startSeconds: cursor,
            endSeconds: activeStart,
            highlightedWordIndex: nil
          )
        )
      }
      let activeEnd = min(max(window.end, activeStart), cueEnd)
      if activeEnd > activeStart {
        segments.append(
          CaptionPresentationSegment(
            startSeconds: activeStart,
            endSeconds: activeEnd,
            highlightedWordIndex: window.index
          )
        )
        cursor = activeEnd
      }
    }
    if cursor < cueEnd {
      segments.append(
        CaptionPresentationSegment(
          startSeconds: cursor,
          endSeconds: cueEnd,
          highlightedWordIndex: nil
        )
      )
    }
    return segments
  }

  static func strokeWidthPercentage(for style: CaptionStyleDescriptor) -> CGFloat {
    guard style.strokeWidth > 0, style.fontSize > 0 else { return 0 }
    // NSAttributedString expresses stroke width as a percentage of font size
    // (positive renders the outline only), while the public style expresses
    // it as a fraction of video height. The stroke is centered on the glyph
    // edge and the fill pass covers the inner half, so the value is doubled
    // to keep the visible outline matching the Flutter preview's shadow.
    return (style.strokeWidth / style.fontSize) * 100 * 2
  }

  /// Locates the character range of the word at `index` inside the cue text
  /// by walking the preceding words. Words are expected to be joined by
  /// single spaces; when the word cannot be located (e.g. the text was edited
  /// after transcription), the highlight is skipped gracefully.
  private static func highlightRange(
    for wordIndex: Int,
    in cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor
  ) -> NSRange {
    let text = displayText(cue.text, style: style) as NSString
    guard wordIndex >= 0, wordIndex < cue.words.count else {
      return NSRange(location: NSNotFound, length: 0)
    }
    var offset = 0
    for i in 0..<wordIndex {
      let word = displayText(cue.words[i].text, style: style)
      guard !word.isEmpty else { continue }
      let found = text.range(of: word, options: [], range: NSRange(location: offset, length: text.length - offset))
      guard found.location != NSNotFound else {
        return NSRange(location: NSNotFound, length: 0)
      }
      offset = found.location + found.length
      if offset < text.length && text.character(at: offset) == 32 {  // space
        offset += 1
      }
    }
    let activeWord = displayText(cue.words[wordIndex].text, style: style)
    let found = text.range(of: activeWord, options: [], range: NSRange(location: offset, length: text.length - offset))
    guard found.location != NSNotFound else {
      return NSRange(location: NSNotFound, length: 0)
    }
    return found
  }
}

/// Immutable raster used by iOS preview caption compositing.
struct CaptionRaster {
  let image: CGImage
  let size: CGSize
  let center: CGPoint
  let startSeconds: Double
  let endSeconds: Double

  func isVisible(at seconds: Double) -> Bool {
    return seconds >= startSeconds && seconds < endSeconds
  }
}

/// Draws cached caption rasters directly into AVPlayerItemVideoOutput frames.
/// Raster creation happens only when the caption state changes; per-frame
/// work is dispatched by TimelineTexture to its serial processing queue.
final class CaptionRenderer {
  private let stateLock = NSLock()
  private var rasters: [CaptionRaster] = []
  private var renderSize = CGSize.zero

  func update(
    cues: [CaptionCueDescriptor],
    style: CaptionStyleDescriptor?,
    renderSize: CGSize,
    totalDuration: CMTime
  ) {
    let nextRasters: [CaptionRaster]
    if let style {
      nextRasters = CaptionLayers.makeCaptionRasters(
        cues: cues,
        style: style,
        renderSize: renderSize,
        totalDuration: totalDuration
      )
    } else {
      nextRasters = []
    }
    stateLock.lock()
    rasters = nextRasters
    self.renderSize = renderSize
    stateLock.unlock()
  }

  func render(over pixelBuffer: CVPixelBuffer, at itemTime: CMTime) {
    guard itemTime.isNumeric else { return }
    let seconds = CMTimeGetSeconds(itemTime)

    stateLock.lock()
    let currentRasters = rasters
    let currentRenderSize = renderSize
    stateLock.unlock()

    let activeRasters = currentRasters.filter { $0.isVisible(at: seconds) }
    guard !activeRasters.isEmpty,
          currentRenderSize.width > 0,
          currentRenderSize.height > 0,
          CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
    else {
      return
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
      CGImageAlphaInfo.premultipliedFirst.rawValue
    guard let context = CGContext(
      data: baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo
    ) else {
      return
    }

    let scaleX = CGFloat(width) / currentRenderSize.width
    let scaleY = CGFloat(height) / currentRenderSize.height
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scaleX, y: -scaleY)

    for raster in activeRasters {
      context.saveGState()
      context.translateBy(x: raster.center.x, y: raster.center.y)
      context.scaleBy(x: 1, y: -1)
      context.setAlpha(1)
      context.draw(
        raster.image,
        in: CGRect(
          x: -raster.size.width / 2,
          y: -raster.size.height / 2,
          width: raster.size.width,
          height: raster.size.height
        )
      )
      context.restoreGState()
    }
    context.flush()
  }
}
