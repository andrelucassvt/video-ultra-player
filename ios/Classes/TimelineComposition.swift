import AVFoundation
import UIKit

enum TimelineCompositionError: Error {
  case emptyClips
  case invalidClip
  case missingVideoTrack(String)
  case cannotCreateCompositionTrack
  case cannotCreateImageVideo
  case cannotCreateExporter
}

struct TimelineClipDescriptor {
  enum MediaType: String {
    case video
    case image
  }

  var path: String
  var type: MediaType
  var durationMs: Int64?
  var alignmentX: CGFloat
  var alignmentY: CGFloat
  var scale: CGFloat

  init?(dictionary: [String: Any]) {
    guard
      let path = dictionary["path"] as? String,
      let typeValue = dictionary["type"] as? String,
      let type = MediaType(rawValue: typeValue)
    else {
      return nil
    }

    let alignment = dictionary["alignment"] as? [String: Any]
    let scaleValue = dictionary["scale"] as? NSNumber
    let durationValue = dictionary["durationMs"] as? NSNumber

    self.path = path
    self.type = type
    self.durationMs = durationValue?.int64Value
    self.alignmentX = CGFloat((alignment?["x"] as? NSNumber)?.doubleValue ?? 0)
    self.alignmentY = CGFloat((alignment?["y"] as? NSNumber)?.doubleValue ?? 0)
    self.scale = max(CGFloat(scaleValue?.doubleValue ?? 1), 0.01)
  }
}

struct TimelineSegment {
  let clipIndex: Int
  let startTime: CMTime
  let duration: CMTime
  let naturalSize: CGSize
  let preferredTransform: CGAffineTransform
}

struct TimelineExportAsset {
  let asset: AVAsset
  let videoComposition: AVVideoComposition?
}

final class TimelineComposition {
  private var clips: [TimelineClipDescriptor] = []
  private var segments: [TimelineSegment] = []
  private var composition: AVMutableComposition?
  private var generatedImageVideoURLs: [URL] = []
  private var renderSize = CGSize(width: 1280, height: 720)

  private(set) var totalDuration = CMTime.zero

  func build(clips: [TimelineClipDescriptor]) throws -> AVPlayerItem {
    guard !clips.isEmpty else {
      throw TimelineCompositionError.emptyClips
    }

    self.clips = clips
    segments = []
    totalDuration = .zero

    let composition = AVMutableComposition()
    guard
      let compositionVideoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw TimelineCompositionError.cannotCreateCompositionTrack
    }

    let compositionAudioTrack = composition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )

    var currentTime = CMTime.zero
    var firstRenderableSize: CGSize?

    for (index, clip) in clips.enumerated() {
      let asset = try asset(for: clip)
      guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
        throw TimelineCompositionError.missingVideoTrack(clip.path)
      }

      let duration = duration(for: clip, asset: asset)
      let timeRange = CMTimeRange(start: .zero, duration: duration)
      try compositionVideoTrack.insertTimeRange(
        timeRange,
        of: sourceVideoTrack,
        at: currentTime
      )

      if let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
         let compositionAudioTrack {
        let audioDuration = CMTimeMinimum(duration, asset.duration)
        try compositionAudioTrack.insertTimeRange(
          CMTimeRange(start: .zero, duration: audioDuration),
          of: sourceAudioTrack,
          at: currentTime
        )
      }

      if firstRenderableSize == nil {
        firstRenderableSize = normalizedSize(
          naturalSize: sourceVideoTrack.naturalSize,
          preferredTransform: sourceVideoTrack.preferredTransform
        )
      }

      segments.append(
        TimelineSegment(
          clipIndex: index,
          startTime: currentTime,
          duration: duration,
          naturalSize: sourceVideoTrack.naturalSize,
          preferredTransform: sourceVideoTrack.preferredTransform
        )
      )
      currentTime = CMTimeAdd(currentTime, duration)
    }

    renderSize = evenSize(firstRenderableSize ?? renderSize)
    totalDuration = currentTime
    self.composition = composition

    let playerItem = AVPlayerItem(asset: composition)
    playerItem.videoComposition = makeVideoComposition(compositionVideoTrack: compositionVideoTrack)
    return playerItem
  }

  func buildExportAsset(clips: [TimelineClipDescriptor]) throws -> TimelineExportAsset {
    let playerItem = try build(clips: clips)
    return TimelineExportAsset(
      asset: playerItem.asset,
      videoComposition: playerItem.videoComposition
    )
  }

  func updateAlignment(clipIndex: Int, x: CGFloat, y: CGFloat) -> AVVideoComposition? {
    guard clips.indices.contains(clipIndex),
          let composition,
          let compositionVideoTrack = composition.tracks(withMediaType: .video).first
    else {
      return nil
    }

    clips[clipIndex].alignmentX = min(max(x, -1), 1)
    clips[clipIndex].alignmentY = min(max(y, -1), 1)
    return makeVideoComposition(compositionVideoTrack: compositionVideoTrack)
  }

  func playbackState(at time: CMTime) -> (clipIndex: Int, localPosition: CMTime) {
    guard !segments.isEmpty else {
      return (0, .zero)
    }

    for segment in segments {
      let endTime = CMTimeAdd(segment.startTime, segment.duration)
      if CMTimeCompare(time, segment.startTime) >= 0 && CMTimeCompare(time, endTime) < 0 {
        return (segment.clipIndex, CMTimeSubtract(time, segment.startTime))
      }
    }

    let lastSegment = segments[segments.count - 1]
    return (lastSegment.clipIndex, lastSegment.duration)
  }

  func dispose() {
    for url in generatedImageVideoURLs {
      try? FileManager.default.removeItem(at: url)
    }
    generatedImageVideoURLs.removeAll()
  }

  private func makeVideoComposition(
    compositionVideoTrack: AVCompositionTrack
  ) -> AVMutableVideoComposition {
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    videoComposition.instructions = segments.map { segment in
      let instruction = AVMutableVideoCompositionInstruction()
      instruction.timeRange = CMTimeRange(
        start: segment.startTime,
        duration: segment.duration
      )

      let layerInstruction = AVMutableVideoCompositionLayerInstruction(
        assetTrack: compositionVideoTrack
      )
      layerInstruction.setTransform(
        transform(for: segment),
        at: segment.startTime
      )
      instruction.layerInstructions = [layerInstruction]
      return instruction
    }
    return videoComposition
  }

  private func transform(for segment: TimelineSegment) -> CGAffineTransform {
    let clip = clips[segment.clipIndex]
    let transformedRect = CGRect(
      origin: .zero,
      size: segment.naturalSize
    ).applying(segment.preferredTransform)

    var transform = segment.preferredTransform.translatedBy(
      x: -transformedRect.origin.x,
      y: -transformedRect.origin.y
    )

    let sourceSize = normalizedSize(
      naturalSize: segment.naturalSize,
      preferredTransform: segment.preferredTransform
    )
    let coverScale = max(
      renderSize.width / max(sourceSize.width, 1),
      renderSize.height / max(sourceSize.height, 1)
    )
    let scale = coverScale * clip.scale
    let scaledWidth = sourceSize.width * scale
    let scaledHeight = sourceSize.height * scale
    let overflowX = max(scaledWidth - renderSize.width, 0)
    let overflowY = max(scaledHeight - renderSize.height, 0)
    let offsetX = -overflowX * ((clip.alignmentX + 1) / 2)
    let offsetY = -overflowY * ((clip.alignmentY + 1) / 2)

    transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    transform = transform.concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    return transform
  }

  private func asset(for clip: TimelineClipDescriptor) throws -> AVURLAsset {
    if clip.type == .video {
      return AVURLAsset(url: URL(fileURLWithPath: clip.path))
    }

    guard let image = UIImage(contentsOfFile: clip.path) else {
      throw TimelineCompositionError.invalidClip
    }

    // Image clips use the planned fallback: generate a short local movie segment.
    let duration = cmTime(fromMilliseconds: clip.durationMs ?? 2_000)
    let url = try makeImageVideo(from: image, duration: duration)
    generatedImageVideoURLs.append(url)
    return AVURLAsset(url: url)
  }

  private func duration(for clip: TimelineClipDescriptor, asset: AVURLAsset) -> CMTime {
    if let durationMs = clip.durationMs {
      let requestedDuration = cmTime(fromMilliseconds: durationMs)
      if clip.type == .video, asset.duration.isNumeric {
        return CMTimeMinimum(requestedDuration, asset.duration)
      }
      return requestedDuration
    }

    if asset.duration.isNumeric && CMTimeCompare(asset.duration, .zero) > 0 {
      return asset.duration
    }

    return cmTime(fromMilliseconds: 2_000)
  }

  private func makeImageVideo(from image: UIImage, duration: CMTime) throws -> URL {
    let targetSize = evenSize(image.size == .zero ? renderSize : image.size)
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "video_ultra_player_image_\(UUID().uuidString).mp4"
    )

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(targetSize.width),
        AVVideoHeightKey: Int(targetSize.height),
      ]
    )
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: Int(targetSize.width),
        kCVPixelBufferHeightKey as String: Int(targetSize.height),
      ]
    )

    guard writer.canAdd(input) else {
      throw TimelineCompositionError.cannotCreateImageVideo
    }
    writer.add(input)

    guard writer.startWriting() else {
      throw writer.error ?? TimelineCompositionError.cannotCreateImageVideo
    }
    writer.startSession(atSourceTime: .zero)

    let fps: Int32 = 30
    let frameCount = max(1, Int(ceil(CMTimeGetSeconds(duration) * Double(fps))))
    for frame in 0..<frameCount {
      while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.005)
      }
      autoreleasepool {
        if let pixelBuffer = makePixelBuffer(image: image, size: targetSize) {
          adaptor.append(
            pixelBuffer,
            withPresentationTime: CMTime(value: Int64(frame), timescale: fps)
          )
        }
      }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
      semaphore.signal()
    }
    semaphore.wait()

    if writer.status == .failed {
      throw writer.error ?? TimelineCompositionError.cannotCreateImageVideo
    }

    return outputURL
  }

  private func makePixelBuffer(image: UIImage, size: CGSize) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes = [
      kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
      kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
    ] as CFDictionary

    let width = Int(size.width)
    let height = Int(size.height)
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32ARGB,
      attributes,
      &pixelBuffer
    )

    guard let pixelBuffer else {
      return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
      )
    else {
      return nil
    }

    context.clear(CGRect(origin: .zero, size: size))
    UIGraphicsPushContext(context)
    image.draw(in: CGRect(origin: .zero, size: size))
    UIGraphicsPopContext()
    return pixelBuffer
  }

  private func normalizedSize(
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform
  ) -> CGSize {
    let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
    return CGSize(width: abs(rect.width), height: abs(rect.height))
  }

  private func evenSize(_ size: CGSize) -> CGSize {
    let width = max(2, Int(size.width.rounded()))
    let height = max(2, Int(size.height.rounded()))
    return CGSize(
      width: width.isMultiple(of: 2) ? width : width + 1,
      height: height.isMultiple(of: 2) ? height : height + 1
    )
  }

  private func cmTime(fromMilliseconds milliseconds: Int64) -> CMTime {
    return CMTime(value: max(milliseconds, 1), timescale: 1_000)
  }
}
