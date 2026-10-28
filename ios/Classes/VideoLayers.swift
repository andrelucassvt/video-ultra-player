import AVFoundation
import UIKit

/// One layer, matching Android (its multi-input preview stalls with more).
let maxVideoLayers = 1

enum VideoLayerError: Error {
  case limitReached
}

/// Picture-in-picture video layer, mirroring the Dart `TimelineVideoLayer`.
///
/// `trimEndMs` is an absolute point in the source (nil = source end). The
/// `source*` fields are resolved natively and never come from Dart.
struct VideoLayerDescriptor: Equatable {
  let id: String
  let path: String
  var startMs: Int64
  var trimStartMs: Int64
  var trimEndMs: Int64?
  var x: CGFloat
  var y: CGFloat
  var widthFraction: CGFloat
  /// Fraction of the frame height; nil keeps the source aspect ratio.
  var heightFraction: CGFloat?
  var opacity: Float
  var sourceDurationMs: Int64 = 0
  var sourceWidth: Int = 0
  var sourceHeight: Int = 0
  /// Gain of the layer's audio in [0, 1]; 0 keeps the layer silent.
  var volume: Double = 1
  var sourceHasAudio = false

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? String,
          let path = dictionary["path"] as? String
    else {
      return nil
    }
    self.id = id
    self.path = path
    self.startMs = max((dictionary["startMs"] as? NSNumber)?.int64Value ?? 0, 0)
    self.trimStartMs = max((dictionary["trimStartMs"] as? NSNumber)?.int64Value ?? 0, 0)
    self.trimEndMs = (dictionary["trimEndMs"] as? NSNumber)?.int64Value
    self.x = CGFloat(min(max((dictionary["x"] as? NSNumber)?.doubleValue ?? 0.5, 0), 1))
    self.y = CGFloat(min(max((dictionary["y"] as? NSNumber)?.doubleValue ?? 0.5, 0), 1))
    self.widthFraction = CGFloat(
      min(max((dictionary["widthFraction"] as? NSNumber)?.doubleValue ?? 0.5, 0.1), 1)
    )
    self.heightFraction = (dictionary["heightFraction"] as? NSNumber).map {
      CGFloat(min(max($0.doubleValue, 0.05), 1))
    }
    self.opacity = Float(min(max((dictionary["opacity"] as? NSNumber)?.doubleValue ?? 1, 0), 1))
    self.volume = min(max((dictionary["volume"] as? NSNumber)?.doubleValue ?? 1, 0), 1)
  }

  /// Channel map in the Dart contract format plus the displayed source size,
  /// answered to `addVideoLayer`.
  func toResponseMap() -> [String: Any] {
    var map: [String: Any] = [
      "id": id,
      "path": path,
      "startMs": startMs,
      "trimStartMs": trimStartMs,
      "x": Double(x),
      "y": Double(y),
      "widthFraction": Double(widthFraction),
      "opacity": Double(opacity),
      "sourceWidth": sourceWidth,
      "sourceHeight": sourceHeight,
      "sourceHasAudio": sourceHasAudio,
    ]
    if volume != 1 { map["volume"] = volume }
    if let trimEndMs { map["trimEndMs"] = trimEndMs }
    if let heightFraction { map["heightFraction"] = Double(heightFraction) }
    return map
  }

  /// True when only the placement (position, size, opacity) differs from
  /// `other` — those edits only need a new video composition, not a rebuild.
  func differsOnlyInPlacement(from other: VideoLayerDescriptor) -> Bool {
    // Volume lives in the audio mix, which the surgical video-composition
    // update does not rebuild: a volume change needs the full rebuild.
    return id == other.id && path == other.path && startMs == other.startMs &&
      volume == other.volume &&
      trimStartMs == other.trimStartMs &&
      (trimEndMs ?? sourceDurationMs) == (other.trimEndMs ?? other.sourceDurationMs)
  }
}

enum VideoLayerTiming {
  /// One video composition instruction range.
  struct InstructionRange: Equatable {
    let range: CMTimeRange
    let segmentIndex: Int
    /// Indices into the layer list, ascending (z-order).
    let activeLayers: [Int]
  }

  /// Splits the main segments at every layer start and end. The result is
  /// contiguous, covers exactly the segments, and lists for each piece the
  /// segment it belongs to and the layers visible in it — AVFoundation rejects
  /// a video composition whose instructions overlap or leave gaps.
  static func instructionRanges(
    segments: [CMTimeRange],
    layers: [CMTimeRange]
  ) -> [InstructionRange] {
    var result: [InstructionRange] = []
    for (segmentIndex, segment) in segments.enumerated() {
      var cuts: [CMTime] = [segment.start, segment.end]
      for layer in layers {
        for edge in [layer.start, layer.end]
        where CMTimeCompare(edge, segment.start) > 0 && CMTimeCompare(edge, segment.end) < 0 {
          cuts.append(edge)
        }
      }
      cuts.sort { CMTimeCompare($0, $1) < 0 }
      var unique: [CMTime] = []
      for cut in cuts where unique.last.map({ CMTimeCompare($0, cut) != 0 }) ?? true {
        unique.append(cut)
      }
      for index in 0..<(unique.count - 1) {
        let range = CMTimeRange(start: unique[index], end: unique[index + 1])
        let active = layers.indices.filter { layerIndex in
          let layer = layers[layerIndex]
          return CMTimeCompare(layer.start, range.start) <= 0 &&
            CMTimeCompare(layer.end, range.end) >= 0
        }
        result.append(
          InstructionRange(range: range, segmentIndex: segmentIndex, activeLayers: active)
        )
      }
    }
    return result
  }

  /// Track-to-render transform of a layer: orient the source, scale it to
  /// `widthFraction` of the frame width — and to `heightFraction` of the frame
  /// height when set (free, stretched), otherwise keeping its aspect — and
  /// center it at the normalized (`x`, `y`); render y points down.
  static func layerTransform(
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    renderSize: CGSize,
    x: CGFloat,
    y: CGFloat,
    widthFraction: CGFloat,
    heightFraction: CGFloat? = nil
  ) -> CGAffineTransform {
    let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    let sourceWidth = max(abs(orientedRect.width), 1)
    let sourceHeight = max(abs(orientedRect.height), 1)
    let targetWidth = renderSize.width * widthFraction
    let scaleX = targetWidth / sourceWidth
    let targetHeight = heightFraction.map { renderSize.height * $0 } ?? sourceHeight * scaleX
    let scaleY = targetHeight / sourceHeight

    return preferredTransform
      .concatenating(
        CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
      )
      .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
      .concatenating(
        CGAffineTransform(
          translationX: renderSize.width * x - targetWidth / 2,
          y: renderSize.height * y - targetHeight / 2
        )
      )
  }
}
