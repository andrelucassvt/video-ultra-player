import AVFoundation
import UIKit

enum GridRendererError: Error {
  case invalidGrid
  case missingVideoTrack(String)
  case cannotCreateCompositionTrack
  case cannotLoadOverlay(String)
}

/// One video cell of a split-screen grid. `rect` is normalized to the canvas
/// (top-left origin), exactly as sent by `TimelineGridCell.toJson`.
struct GridCellDescriptor {
  let path: String
  let rect: CGRect

  init?(dictionary: [String: Any]) {
    guard
      let path = dictionary["path"] as? String,
      let x = (dictionary["x"] as? NSNumber)?.doubleValue,
      let y = (dictionary["y"] as? NSNumber)?.doubleValue,
      let width = (dictionary["width"] as? NSNumber)?.doubleValue,
      let height = (dictionary["height"] as? NSNumber)?.doubleValue,
      width > 0,
      height > 0
    else {
      return nil
    }
    self.path = path
    self.rect = CGRect(x: x, y: y, width: width, height: height)
  }
}

struct GridCompositionDescriptor {
  let renderSize: CGSize
  let cells: [GridCellDescriptor]
  let overlayImagePath: String?
  let audioCellIndex: Int?
  let maxDurationMs: Int64?

  init?(dictionary: [String: Any]) {
    guard
      let width = (dictionary["width"] as? NSNumber)?.intValue,
      let height = (dictionary["height"] as? NSNumber)?.intValue,
      width > 0,
      height > 0,
      let rawCells = dictionary["cells"] as? [[String: Any]],
      !rawCells.isEmpty
    else {
      return nil
    }
    let cells = rawCells.compactMap(GridCellDescriptor.init(dictionary:))
    guard cells.count == rawCells.count else { return nil }

    self.renderSize = CGSize(width: width, height: height)
    self.cells = cells
    self.overlayImagePath = dictionary["overlayImagePath"] as? String
    self.audioCellIndex = (dictionary["audioCellIndex"] as? NSNumber)?.intValue
    self.maxDurationMs = (dictionary["maxDurationMs"] as? NSNumber)?.int64Value
  }
}

/// Builds the export asset of a split-screen grid: every cell is its own
/// composition track playing at the same time, scaled to cover its cell and
/// cropped around the center. Shorter videos loop until the longest one ends.
/// The caller-provided overlay PNG (background, shapes and still images) is
/// burned on top through `AVVideoCompositionCoreAnimationTool`, which is valid
/// here because a grid is only ever rendered offline.
enum GridRenderer {
  /// Reading tracks is blocking; grids are assembled off the platform thread.
  static let buildQueue = DispatchQueue(
    label: "video_ultra_player.grid.build",
    qos: .userInitiated
  )

  private static let frameRate: Int32 = 30

  static func buildExportAsset(grid: GridCompositionDescriptor) throws -> TimelineExportAsset {
    let renderSize = grid.renderSize
    let composition = AVMutableComposition()

    let sources: [(cell: GridCellDescriptor, asset: AVURLAsset, video: AVAssetTrack)] =
      try grid.cells.map { cell in
        let asset = AVURLAsset(url: URL(fileURLWithPath: cell.path))
        guard let video = asset.tracks(withMediaType: .video).first,
              video.timeRange.duration.isNumeric,
              video.timeRange.duration > .zero
        else {
          throw GridRendererError.missingVideoTrack(cell.path)
        }
        return (cell, asset, video)
      }

    var totalDuration = sources
      .map { $0.video.timeRange.duration }
      .reduce(CMTime.zero) { CMTimeMaximum($0, $1) }
    if let maxDurationMs = grid.maxDurationMs, maxDurationMs > 0 {
      totalDuration = CMTimeMinimum(
        totalDuration,
        CMTime(value: maxDurationMs, timescale: 1000)
      )
    }
    guard totalDuration > .zero else { throw GridRendererError.invalidGrid }

    var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
    for (index, source) in sources.enumerated() {
      guard let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      ) else {
        throw GridRendererError.cannotCreateCompositionTrack
      }
      try insertLooping(
        source.video,
        sourceRange: source.video.timeRange,
        into: videoTrack,
        total: totalDuration
      )

      if index == grid.audioCellIndex,
         let sourceAudio = source.asset.tracks(withMediaType: .audio).first,
         sourceAudio.timeRange.duration > .zero,
         let audioTrack = composition.addMutableTrack(
           withMediaType: .audio,
           preferredTrackID: kCMPersistentTrackID_Invalid
         ) {
        try insertLooping(
          sourceAudio,
          sourceRange: sourceAudio.timeRange,
          into: audioTrack,
          total: totalDuration
        )
      }

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
      let placement = placement(
        for: source.cell,
        naturalSize: source.video.naturalSize,
        preferredTransform: source.video.preferredTransform,
        renderSize: renderSize
      )
      layerInstruction.setCropRectangle(placement.crop, at: .zero)
      layerInstruction.setTransform(placement.transform, at: .zero)
      layerInstructions.append(layerInstruction)
    }

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
    instruction.backgroundColor = UIColor.black.cgColor
    instruction.layerInstructions = layerInstructions

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)
    // CoreAnimationTool rasterizes in SDR; pin the working space to BT.709 so
    // HDR sources are tone-mapped instead of washing out the overlay colors.
    videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

    if let overlayImagePath = grid.overlayImagePath, !overlayImagePath.isEmpty {
      guard let image = decodedOverlayImage(path: overlayImagePath, renderSize: renderSize) else {
        throw GridRendererError.cannotLoadOverlay(overlayImagePath)
      }
      // Same synthetic-track approach as text overlays: the post-processing
      // initializer crashes on several Simulator runtimes.
      let overlayTrackID = composition.unusedTrackID()
      videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        additionalLayer: overlayLayer(image: image, renderSize: renderSize),
        asTrackID: overlayTrackID
      )
      TextOverlayLayers.prependOverlayTrack(overlayTrackID, to: [instruction])
    }

    videoComposition.instructions = [instruction]
    return TimelineExportAsset(asset: composition, videoComposition: videoComposition, audioMix: nil)
  }

  /// Redraws the overlay PNG into an 8-bit premultiplied sRGB bitmap at the
  /// render size. The file comes straight from Flutter and may be lazily
  /// decoded or use a wide-gamut/16-bit layout; on device Core Animation's
  /// offline renderer can rasterize such an image as an opaque black frame,
  /// which hides every cell below the overlay track.
  private static func decodedOverlayImage(path: String, renderSize: CGSize) -> CGImage? {
    guard let source = UIImage(contentsOfFile: path)?.cgImage else { return nil }
    let width = Int(renderSize.width)
    let height = Int(renderSize.height)
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.clear(bounds)
    context.interpolationQuality = .high
    context.draw(source, in: bounds)
    return context.makeImage()
  }

  /// Built off the main thread, so the layer tree lives in an explicit
  /// transaction: an implicit one is only committed by a run loop, which the
  /// build queue does not have.
  private static func overlayLayer(image: CGImage, renderSize: CGSize) -> CALayer {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: renderSize)
    parentLayer.isGeometryFlipped = true

    let imageLayer = CALayer()
    imageLayer.frame = parentLayer.bounds
    imageLayer.contents = image
    imageLayer.contentsGravity = .resize
    parentLayer.addSublayer(imageLayer)
    return parentLayer
  }

  /// Repeats `sourceRange` back to back until `total` is filled.
  private static func insertLooping(
    _ source: AVAssetTrack,
    sourceRange: CMTimeRange,
    into track: AVMutableCompositionTrack,
    total: CMTime
  ) throws {
    guard sourceRange.duration > .zero else { return }
    var cursor = CMTime.zero
    while cursor < total {
      let duration = CMTimeMinimum(sourceRange.duration, CMTimeSubtract(total, cursor))
      try track.insertTimeRange(
        CMTimeRange(start: sourceRange.start, duration: duration),
        of: source,
        at: cursor
      )
      cursor = CMTimeAdd(cursor, duration)
    }
  }

  /// Cover-fit of the oriented source into the cell: returns the crop in the
  /// source (pre-transform) space and the transform that lands the cropped
  /// region exactly on the cell.
  private static func placement(
    for cell: GridCellDescriptor,
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform,
    renderSize: CGSize
  ) -> (crop: CGRect, transform: CGAffineTransform) {
    let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    let orient = preferredTransform.concatenating(
      CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
    )
    let sourceSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))

    let cellRect = CGRect(
      x: cell.rect.minX * renderSize.width,
      y: cell.rect.minY * renderSize.height,
      width: cell.rect.width * renderSize.width,
      height: cell.rect.height * renderSize.height
    )
    let scale = max(
      cellRect.width / max(sourceSize.width, 1),
      cellRect.height / max(sourceSize.height, 1)
    )
    let visibleSize = CGSize(width: cellRect.width / scale, height: cellRect.height / scale)
    let orientedCrop = CGRect(
      x: (sourceSize.width - visibleSize.width) / 2,
      y: (sourceSize.height - visibleSize.height) / 2,
      width: visibleSize.width,
      height: visibleSize.height
    )

    let transform = orient
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(
        CGAffineTransform(
          translationX: cellRect.minX - orientedCrop.minX * scale,
          y: cellRect.minY - orientedCrop.minY * scale
        )
      )
    let crop = orientedCrop.applying(orient.inverted()).standardized
    return (crop, transform)
  }
}
