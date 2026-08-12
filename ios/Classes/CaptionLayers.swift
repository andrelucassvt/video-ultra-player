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
  /// frame. In karaoke mode one raster per word (the full cue text with that
  /// word highlighted) is produced, each visible during its word window.
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
    let startSeconds = max(Double(cue.startMs) / 1_000, 0)
    let endSeconds = min(Double(cue.endMs) / 1_000, max(totalSeconds, 0))
    guard endSeconds > startSeconds else {
      return []
    }

    if !style.karaoke || cue.words.isEmpty {
      guard let raster = makeRaster(
        text: displayText(cue.text, style: style),
        highlightRange: nil,
        cue: cue,
        style: style,
        renderSize: renderSize,
        startSeconds: startSeconds,
        endSeconds: endSeconds
      ) else {
        return []
      }
      return [raster]
    }

    return cue.words.enumerated().compactMap { index, word in
      let wordStart = max(Double(word.startMs) / 1_000, startSeconds)
      let wordEnd = min(Double(word.endMs) / 1_000, endSeconds)
      guard wordEnd > wordStart else { return nil }
      let range = highlightRange(for: index, in: cue, style: style)
      return makeRaster(
        text: displayText(cue.text, style: style),
        highlightRange: range,
        cue: cue,
        style: style,
        renderSize: renderSize,
        startSeconds: wordStart,
        endSeconds: wordEnd
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
    let attributed = attributedText(
      text: text,
      font: font,
      style: style,
      highlightRange: highlightRange
    )

    let boundingRect = attributed.boundingRect(
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
      attributed.draw(
        with: CGRect(
          x: padding - boundingRect.minX,
          y: padding - boundingRect.minY,
          width: max(boundingRect.width, fontSize),
          height: max(boundingRect.height, fontSize)
        ),
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
  /// One layer per cue with a discrete opacity animation on `[start, end)`;
  /// in karaoke mode a second highlight layer per word animates on the word
  /// window over the base cue text.
  private static func makeExportCueLayer(
    cue: CaptionCueDescriptor,
    style: CaptionStyleDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> CALayer? {
    let startSeconds = max(Double(cue.startMs) / 1_000, 0)
    let endSeconds = min(Double(cue.endMs) / 1_000, max(totalSeconds, 0))
    guard endSeconds > startSeconds else {
      return nil
    }

    let text = displayText(cue.text, style: style)
    let container = CALayer()
    container.frame = CGRect(origin: .zero, size: renderSize)

    guard let baseLayer = makeExportTextLayer(
      text: text,
      highlightRange: nil,
      style: style,
      renderSize: renderSize,
      totalSeconds: totalSeconds,
      startSeconds: startSeconds,
      endSeconds: endSeconds
    ) else {
      return nil
    }
    container.addSublayer(baseLayer)

    if style.karaoke && !cue.words.isEmpty {
      for (index, word) in cue.words.enumerated() {
        let wordStart = max(Double(word.startMs) / 1_000, startSeconds)
        let wordEnd = min(Double(word.endMs) / 1_000, endSeconds)
        guard wordEnd > wordStart else { continue }
        guard let highlightLayer = makeExportTextLayer(
          text: text,
          highlightRange: highlightRange(for: index, in: cue, style: style),
          style: style,
          renderSize: renderSize,
          totalSeconds: totalSeconds,
          startSeconds: wordStart,
          endSeconds: wordEnd
        ) else {
          continue
        }
        container.addSublayer(highlightLayer)
      }
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
  ) -> CATextLayer? {
    let fontSize = style.fontSize * renderSize.height
    let font = UIFont.systemFont(ofSize: max(fontSize, 1), weight: .bold)
    let attributed = attributedText(
      text: text,
      font: font,
      style: style,
      highlightRange: highlightRange
    )

    let boundingRect = attributed.boundingRect(
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

    let layer = CATextLayer()
    layer.string = attributed
    layer.isWrapped = true
    layer.alignmentMode = .center
    layer.contentsScale = UIScreen.main.scale
    layer.allowsEdgeAntialiasing = true
    layer.frame = CGRect(
      x: center.x - boxSize.width / 2,
      y: center.y - boxSize.height / 2,
      width: boxSize.width,
      height: boxSize.height
    )
    layer.opacity = 0

    if style.backgroundOpacity > 0 {
      layer.backgroundColor = UIColor.black
        .withAlphaComponent(style.backgroundOpacity)
        .cgColor
    }

    // CoreAnimationTool is an offline renderer. A discrete opacity animation
    // is reliable at both edges of [start, end), unlike CALayer timing fields
    // whose fill behavior can leak the model-layer opacity outside the window.
    let startFraction = startSeconds / totalSeconds
    let endFraction = endSeconds / totalSeconds
    let visibility = CAKeyframeAnimation(keyPath: "opacity")
    if startFraction <= 0 {
      visibility.values = [1, 0]
      visibility.keyTimes = [0, NSNumber(value: endFraction)]
    } else {
      visibility.values = [0, 1, 0]
      visibility.keyTimes = [
        0,
        NSNumber(value: startFraction),
        NSNumber(value: endFraction),
      ]
    }
    visibility.calculationMode = .discrete
    visibility.beginTime = AVCoreAnimationBeginTimeAtZero
    visibility.duration = totalSeconds
    visibility.fillMode = .both
    visibility.isRemovedOnCompletion = false
    layer.add(visibility, forKey: "captionVisibility")

    return layer
  }

  // MARK: - Shared helpers

  private static func displayText(_ text: String, style: CaptionStyleDescriptor) -> String {
    return style.uppercase ? text.uppercased() : text
  }

  private static func attributedText(
    text: String,
    font: UIFont,
    style: CaptionStyleDescriptor,
    highlightRange: NSRange?
  ) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .paragraphStyle: paragraph,
      .foregroundColor: UIColor(argb: style.color),
    ]
    if style.strokeWidth > 0 {
      // Negative stroke width = fill + outline, matching the Android renderer.
      attributes[.strokeColor] = UIColor.black
      attributes[.strokeWidth] = -style.strokeWidth * font.pointSize
    }

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
