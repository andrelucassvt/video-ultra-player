import AVFoundation
import CoreText
import UIKit

/// Builds the CALayer tree that burns text overlays into the rendered video.
///
/// The layer tree is attached to the `AVVideoComposition` via
/// `AVVideoCompositionCoreAnimationTool` in `TimelineComposition`, so the
/// same tree renders in the preview (AVPlayerItem) and in the exported MP4.
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

    let totalSeconds = totalDuration.isNumeric ? CMTimeGetSeconds(totalDuration) : 0

    for overlay in overlays {
      guard let textLayer = makeTextLayer(
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

  private static func makeTextLayer(
    overlay: TextOverlayDescriptor,
    renderSize: CGSize,
    totalSeconds: Double
  ) -> CATextLayer? {
    let startSeconds = Double(overlay.startMs) / 1_000
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
    layer.opacity = Float(overlay.opacity)

    if overlay.backgroundColor >> 24 > 0 {
      layer.backgroundColor = UIColor(argb: overlay.backgroundColor).cgColor
    }

    if overlay.rotationDegrees != 0 {
      layer.setValue(
        overlay.rotationDegrees * .pi / 180,
        forKeyPath: "transform.rotation.z"
      )
    }

    // Visibility window: the layer exists only within [startSeconds, endSeconds).
    // `isRemovedOnCompletion` is a CAAnimation-only property, so the window is
    // expressed through the layer's media timing fields alone.
    layer.beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds
    layer.duration = endSeconds - startSeconds
    layer.fillMode = .forwards

    // Known CoreAnimationTool quirk: if the text shows outside its window on
    // manual testing, replace the beginTime/duration approach with opacity
    // keyframes (0→1 at start, 1→0 at end) anchored on
    // AVCoreAnimationBeginTimeAtZero.
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

private extension UIColor {
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
