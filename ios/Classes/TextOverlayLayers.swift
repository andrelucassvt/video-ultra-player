import AVFoundation
import CoreText
import UIKit

/// Builds the CALayer tree that burns text overlays into the rendered video.
///
/// Export attaches this tree as an additional synthetic input of
/// `AVVideoCompositionCoreAnimationTool`.
/// Preview rasterizes the same attributed text into `TimelineTexture` frames,
/// because Apple only supports the animation tool for offline rendering.
enum TextOverlayLayers {
  /// Root layer for all text overlays, sized to the render frame.
  ///
  /// `isGeometryFlipped = true` gives top-left origin coordinates, matching
  /// the normalized `x`/`y` values coming from the Dart model.
  static func makeTextOverlayParentLayer(
    overlays: [TextOverlayDescriptor],
    renderSize: CGSize,
    totalDuration: CMTime
  ) -> CALayer {
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.isGeometryFlipped = true

    let totalSeconds = totalDuration.isNumeric
      ? max(CMTimeGetSeconds(totalDuration), 0)
      : 0
    for overlay in overlays {
      guard let textLayer = makeExportTextLayer(
        overlay: overlay,
        renderSize: renderSize,
        totalSeconds: totalSeconds
      ) else {
        continue
      }
      parentLayer.addSublayer(textLayer)
    }
    return parentLayer
  }

  /// Rasterizes text once per committed state so preview can draw the cached
  /// images into the texture pixel buffer without doing text layout per frame.
  static func makeTextOverlayRasters(
    overlays: [TextOverlayDescriptor],
    renderSize: CGSize,
    totalDuration: CMTime
  ) -> [TextOverlayRaster] {
    let totalSeconds = totalDuration.isNumeric
      ? max(CMTimeGetSeconds(totalDuration), 0)
      : 0
    guard totalSeconds > 0 else { return [] }

    return overlays.compactMap { overlay in
      makeTextOverlayRaster(
        overlay: overlay,
        renderSize: renderSize,
        totalSeconds: totalSeconds
      )
    }
  }

  /// Inserts the synthetic Core Animation input before the video input so
  /// every composition segment renders text above its source frame.
  static func prependOverlayTrack(
    _ trackID: CMPersistentTrackID,
    to instructions: [AVMutableVideoCompositionInstruction]
  ) {
    for instruction in instructions {
      let overlayInstruction = AVMutableVideoCompositionLayerInstruction()
      overlayInstruction.trackID = trackID
      instruction.layerInstructions.insert(overlayInstruction, at: 0)
    }
  }

  /// Resolves the font for an overlay: `fontPath` (custom .ttf/.otf) wins,
  /// then `fontFamily`, then the system font. Never fails — invalid or
  /// missing fonts fall back gracefully.
  static func resolveFont(fontFamily: String?, fontPath: String?, size: CGFloat) -> UIFont {
    if let fontPath, FileManager.default.fileExists(atPath: fontPath) {
      let url = URL(fileURLWithPath: fontPath) as CFURL
      // Ignore the error — re-registering an already-registered font returns
      // an error that must not fail the timeline.
      var registrationError: Unmanaged<CFError>?
      CTFontManagerRegisterFontsForURL(url, .process, &registrationError)
      if let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor])?.first {
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        let postScriptName = CTFontCopyPostScriptName(ctFont) as String
        if let font = UIFont(name: postScriptName, size: size) {
          return font
        }
      }
    }
    if let fontFamily, let font = UIFont(name: fontFamily, size: size) {
      return font
    }
    return UIFont.systemFont(ofSize: size)
  }

  private static func makeTextOverlayRaster(
    overlay: TextOverlayDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> TextOverlayRaster? {
    let startSeconds = max(Double(overlay.startMs) / 1_000, 0)
    let endSeconds = min(Double(overlay.endMs) / 1_000, max(totalSeconds, 0))
    guard endSeconds > startSeconds, totalSeconds > 0 else {
      return nil
    }

    let fontSize = overlay.fontSize * renderSize.height
    let font = resolveFont(
      fontFamily: overlay.fontFamily,
      fontPath: overlay.fontPath,
      size: fontSize
    )

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = textAlignment(for: overlay.textAlign)

    let color = UIColor(argb: overlay.color)
    let attributed = NSAttributedString(
      string: overlay.text,
      attributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
      ]
    )

    let boundingRect = attributed.boundingRect(
      with: CGSize(width: renderSize.width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )

    // Small padding so a background box does not hug the glyphs.
    let padding: CGFloat = fontSize * 0.3
    let boxSize = CGSize(
      width: max(ceil(boundingRect.width) + padding * 2, fontSize),
      height: max(ceil(boundingRect.height) + padding * 2, fontSize)
    )
    let center = CGPoint(
      x: overlay.x * renderSize.width,
      y: overlay.y * renderSize.height
    )

    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: boxSize, format: format)
    let image = renderer.image { context in
      context.cgContext.clear(CGRect(origin: .zero, size: boxSize))
      if overlay.backgroundColor >> 24 > 0 {
        UIColor(argb: overlay.backgroundColor).setFill()
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

    return TextOverlayRaster(
      image: cgImage,
      size: boxSize,
      center: center,
      rotationRadians: CGFloat(overlay.rotationDegrees * .pi / 180),
      opacity: CGFloat(overlay.opacity),
      startSeconds: startSeconds,
      endSeconds: endSeconds
    )
  }

  /// Uses CATextLayer for offline export instead of assigning a raster image
  /// to CALayer.contents. The latter makes Core Animation bridge the image
  /// through IOSurface and crashes the iOS compositor on some runtimes.
  private static func makeExportTextLayer(
    overlay: TextOverlayDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> CATextLayer? {
    let startSeconds = max(Double(overlay.startMs) / 1_000, 0)
    let endSeconds = min(Double(overlay.endMs) / 1_000, max(totalSeconds, 0))
    guard endSeconds > startSeconds, totalSeconds > 0 else {
      return nil
    }

    let fontSize = overlay.fontSize * renderSize.height
    let font = resolveFont(
      fontFamily: overlay.fontFamily,
      fontPath: overlay.fontPath,
      size: fontSize
    )

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = textAlignment(for: overlay.textAlign)
    let attributed = NSAttributedString(
      string: overlay.text,
      attributes: [
        .font: font,
        .foregroundColor: UIColor(argb: overlay.color),
        .paragraphStyle: paragraph,
      ]
    )

    let boundingRect = attributed.boundingRect(
      with: CGSize(width: renderSize.width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let padding: CGFloat = fontSize * 0.3
    let boxSize = CGSize(
      width: max(ceil(boundingRect.width) + padding * 2, fontSize),
      height: max(ceil(boundingRect.height) + padding * 2, fontSize)
    )
    let center = CGPoint(
      x: overlay.x * renderSize.width,
      y: overlay.y * renderSize.height
    )

    let layer = CATextLayer()
    layer.string = attributed
    layer.isWrapped = true
    layer.alignmentMode = alignmentMode(for: overlay.textAlign)
    layer.contentsScale = UIScreen.main.scale
    layer.allowsEdgeAntialiasing = true
    layer.frame = CGRect(
      x: center.x - boxSize.width / 2,
      y: center.y - boxSize.height / 2,
      width: boxSize.width,
      height: boxSize.height
    )
    layer.opacity = 0

    if overlay.backgroundColor >> 24 > 0 {
      layer.backgroundColor = UIColor(argb: overlay.backgroundColor).cgColor
    }
    if overlay.rotationDegrees != 0 {
      layer.setValue(
        overlay.rotationDegrees * .pi / 180,
        forKeyPath: "transform.rotation.z"
      )
    }

    // CoreAnimationTool is an offline renderer. A discrete opacity animation
    // is reliable at both edges of [start, end), unlike CALayer timing fields
    // whose fill behavior can leak the model-layer opacity outside the window.
    let startFraction = startSeconds / totalSeconds
    let endFraction = endSeconds / totalSeconds
    let visibility = CAKeyframeAnimation(keyPath: "opacity")
    if startFraction <= 0 {
      visibility.values = [overlay.opacity, 0]
      visibility.keyTimes = [0, NSNumber(value: endFraction)]
    } else {
      visibility.values = [0, overlay.opacity, 0]
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
    layer.add(visibility, forKey: "timelineVisibility")

    return layer
  }

  private static func textAlignment(for align: TextOverlayTextAlign) -> NSTextAlignment {
    switch align {
    case .left: return .left
    case .center: return .center
    case .right: return .right
    }
  }

  private static func alignmentMode(for align: TextOverlayTextAlign) -> CATextLayerAlignmentMode {
    switch align {
    case .left: return .left
    case .center: return .center
    case .right: return .right
    }
  }
}

/// Immutable raster used by iOS preview text compositing.
struct TextOverlayRaster {
  let image: CGImage
  let size: CGSize
  let center: CGPoint
  let rotationRadians: CGFloat
  let opacity: CGFloat
  let startSeconds: Double
  let endSeconds: Double

  func isVisible(at seconds: Double) -> Bool {
    return seconds >= startSeconds && seconds < endSeconds
  }
}

/// Draws cached overlay rasters directly into AVPlayerItemVideoOutput frames.
/// Raster creation happens only when the overlay state changes; per-frame work
/// is dispatched by TimelineTexture to its serial processing queue.
final class TimelineTextOverlayRenderer {
  private let stateLock = NSLock()
  private var rasters: [TextOverlayRaster] = []
  private var renderSize = CGSize.zero

  func update(
    overlays: [TextOverlayDescriptor],
    renderSize: CGSize,
    totalDuration: CMTime
  ) {
    let nextRasters = TextOverlayLayers.makeTextOverlayRasters(
      overlays: overlays,
      renderSize: renderSize,
      totalDuration: totalDuration
    )
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
      context.rotate(by: raster.rotationRadians)
      // The pixel-buffer context is flipped to top-left coordinates above,
      // but CGContext.draw(CGImage) still uses Quartz image orientation.
      // Flip only the raster around its center so glyphs stay upright without
      // changing the overlay's top-left position or clockwise rotation.
      context.scaleBy(x: 1, y: -1)
      context.setAlpha(raster.opacity)
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

extension UIColor {
  /// Creates a UIColor from an ARGB `UInt32` (as used on the method channel).
  convenience init(argb: UInt32) {
    self.init(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}
