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
  /// Trim start offset within the source file (milliseconds).
  var trimStartMs: Int64?
  /// Trim end point within the source file (milliseconds). Takes precedence
  /// over `durationMs` for video clips.
  var trimEndMs: Int64?
  /// Duration of the transition to the next clip (nil = hard cut).
  var transitionToNextMs: Int64?

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
    self.trimStartMs = (dictionary["trimStartMs"] as? NSNumber)?.int64Value
    self.trimEndMs = (dictionary["trimEndMs"] as? NSNumber)?.int64Value
    if let transition = dictionary["transitionToNext"] as? [String: Any] {
      self.transitionToNextMs = (transition["durationMs"] as? NSNumber)?.int64Value
    }
  }
}

struct TimelineCompositionConfig {
  enum OutputAspectRatio: String {
    case ratio16x9
    case ratio9x16
    case ratio1x1
    case original
  }

  let aspectRatio: OutputAspectRatio
  let baseWidth: Int

  init(dictionary: [String: Any]? = nil) {
    let aspectRatioValue = dictionary?["aspectRatio"] as? String
    let baseWidth = dictionary?["baseWidth"] as? NSNumber

    self.aspectRatio = OutputAspectRatio(rawValue: aspectRatioValue ?? "") ?? .original
    self.baseWidth = max(baseWidth?.intValue ?? 1080, 1)
  }
}

struct TimelineSegment {
  let clipIndex: Int
  let startTime: CMTime
  let duration: CMTime
  let naturalSize: CGSize
  let preferredTransform: CGAffineTransform
  let videoTrack: AVCompositionTrack
  let audioTrack: AVCompositionTrack?
}

struct TimelineExportAsset {
  let asset: AVAsset
  let videoComposition: AVVideoComposition?
  let audioMix: AVAudioMix?
}

final class TimelineComposition {
  private struct PreparedClip {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let sourceStart: CMTime
    let duration: CMTime
    let renderableSize: CGSize
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
  }

  private var clips: [TimelineClipDescriptor] = []
  private var segments: [TimelineSegment] = []
  private var composition: AVMutableComposition?
  private var imageVideoCache: [String: URL] = [:]
  private var generatedImageVideoURLs: [URL] = []
  private var renderSize = CGSize(width: 1280, height: 720)
  private var audioMix: AVAudioMix?

  private(set) var totalDuration = CMTime.zero

  // MARK: - Build

  func build(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig = TimelineCompositionConfig()
  ) throws -> AVPlayerItem {
    guard !clips.isEmpty else {
      throw TimelineCompositionError.emptyClips
    }

    self.clips = clips
    segments = []
    totalDuration = .zero
    audioMix = nil

    let preparedClips = try clips.map { clip -> PreparedClip in
      let asset = try resolvedAsset(for: clip)
      guard let sourceVideoTrack = asset.tracks(withMediaType: .video).first else {
        throw TimelineCompositionError.missingVideoTrack(clip.path)
      }
      let (sourceStart, effectiveDuration) = effectiveRange(for: clip, asset: asset)
      return PreparedClip(
        asset: asset,
        videoTrack: sourceVideoTrack,
        audioTrack: asset.tracks(withMediaType: .audio).first,
        sourceStart: sourceStart,
        duration: effectiveDuration,
        renderableSize: normalizedSize(
          naturalSize: sourceVideoTrack.naturalSize,
          preferredTransform: sourceVideoTrack.preferredTransform
        ),
        naturalSize: sourceVideoTrack.naturalSize,
        preferredTransform: sourceVideoTrack.preferredTransform
      )
    }

    let mutableComposition = AVMutableComposition()
    guard
      let videoTrack = mutableComposition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw TimelineCompositionError.cannotCreateCompositionTrack
    }

    let audioTrack = mutableComposition.addMutableTrack(
      withMediaType: .audio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )

    let firstRenderableSize = preparedClips.first?.renderableSize ?? renderSize
    renderSize = renderSize(for: config, firstRenderableSize: firstRenderableSize)

    var startTime = CMTime.zero
    for (index, prepared) in preparedClips.enumerated() {
      let sourceRange = CMTimeRange(start: prepared.sourceStart, duration: prepared.duration)
      try videoTrack.insertTimeRange(sourceRange, of: prepared.videoTrack, at: startTime)

      if let sourceAudioTrack = prepared.audioTrack, let audioTrack {
        let maxAudioDuration = CMTimeSubtract(prepared.asset.duration, prepared.sourceStart)
        let audioDuration = CMTimeMinimum(prepared.duration, maxAudioDuration)
        if isPositive(audioDuration) {
          try audioTrack.insertTimeRange(
            CMTimeRange(start: prepared.sourceStart, duration: audioDuration),
            of: sourceAudioTrack,
            at: startTime
          )
        }
      }

      segments.append(
        TimelineSegment(
          clipIndex: index,
          startTime: startTime,
          duration: prepared.duration,
          naturalSize: prepared.naturalSize,
          preferredTransform: prepared.preferredTransform,
          videoTrack: videoTrack,
          audioTrack: audioTrack
        )
      )
      startTime = CMTimeAdd(startTime, prepared.duration)
    }

    totalDuration = startTime
    audioMix = makeAudioMix()
    self.composition = mutableComposition

    let playerItem = AVPlayerItem(asset: mutableComposition)
    playerItem.videoComposition = makeVideoComposition()
    playerItem.audioMix = audioMix
    return playerItem
  }

  /// Rebuilds from the current `clips` list without accepting new clips.
  func rebuildAsPlayerItem(config: TimelineCompositionConfig) throws -> AVPlayerItem {
    return try build(clips: clips, config: config)
  }

  func buildExportAsset(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig = TimelineCompositionConfig()
  ) throws -> TimelineExportAsset {
    let playerItem = try build(clips: clips, config: config)
    return TimelineExportAsset(
      asset: playerItem.asset,
      videoComposition: playerItem.videoComposition,
      audioMix: playerItem.audioMix
    )
  }

  /// Builds an export asset from the current (edited) clips list.
  func buildCurrentExportAsset(config: TimelineCompositionConfig) throws -> TimelineExportAsset {
    return try buildExportAsset(clips: clips, config: config)
  }

  // MARK: - Mutation

  func trimClip(at index: Int, trimStartMs: Int64?, trimEndMs: Int64?) {
    guard clips.indices.contains(index) else { return }
    if let start = trimStartMs { clips[index].trimStartMs = start }
    if let end = trimEndMs { clips[index].trimEndMs = end }
    clips[index].durationMs = nil  // trimEnd takes precedence
  }

  /// Splits the clip at `index` at `atLocalMs` milliseconds from its trim-start.
  /// Returns false if the index is out of range or the split position is invalid.
  @discardableResult
  func splitClip(at index: Int, atLocalMs: Int64) -> Bool {
    guard clips.indices.contains(index), atLocalMs > 0 else { return false }
    let clip = clips[index]
    let effectiveTrimStart: Int64 = clip.trimStartMs ?? 0
    let absSplitMs = effectiveTrimStart + atLocalMs

    var clipA = clip
    clipA.trimStartMs = effectiveTrimStart == 0 ? nil : effectiveTrimStart
    clipA.trimEndMs = absSplitMs
    clipA.durationMs = nil
    clipA.transitionToNextMs = nil  // hard cut at split boundary

    var clipB = clip
    clipB.trimStartMs = absSplitMs
    // Keep original trimEnd; if only durationMs was set, compute explicit end
    if clipB.trimEndMs == nil, let durMs = clip.durationMs {
      clipB.trimEndMs = effectiveTrimStart + durMs
    }
    clipB.durationMs = nil

    clips.remove(at: index)
    clips.insert(clipB, at: index)
    clips.insert(clipA, at: index)
    return true
  }

  func insertClip(_ descriptor: TimelineClipDescriptor, at index: Int) {
    let safeIndex = max(0, min(index, clips.count))
    clips.insert(descriptor, at: safeIndex)
  }

  func removeClip(at index: Int) {
    guard clips.indices.contains(index) else { return }
    clips.remove(at: index)
  }

  func moveClip(from: Int, to: Int) {
    guard clips.indices.contains(from), to >= 0, to <= clips.count - 1,
          from != to else { return }
    let clip = clips.remove(at: from)
    clips.insert(clip, at: min(to, clips.count))
  }

  func replaceClip(at index: Int, with descriptor: TimelineClipDescriptor) {
    guard clips.indices.contains(index) else { return }
    clips[index] = descriptor
  }

  // MARK: - Queries

  func updateAlignment(clipIndex: Int, x: CGFloat, y: CGFloat) -> AVVideoComposition? {
    guard clips.indices.contains(clipIndex), composition != nil else {
      return nil
    }

    clips[clipIndex].alignmentX = min(max(x, -1), 1)
    clips[clipIndex].alignmentY = min(max(y, -1), 1)
    return makeVideoComposition()
  }

  func startTime(forClipIndex clipIndex: Int) -> CMTime? {
    return segments.first(where: { $0.clipIndex == clipIndex })?.startTime
  }

  func playbackState(at time: CMTime) -> (clipIndex: Int, localPosition: CMTime) {
    guard !segments.isEmpty else {
      return (0, .zero)
    }

    let clampedTime = CMTimeMinimum(CMTimeMaximum(time, .zero), totalDuration)
    for segment in segments.reversed() {
      let endTime = CMTimeAdd(segment.startTime, segment.duration)
      if CMTimeCompare(clampedTime, segment.startTime) >= 0 &&
          CMTimeCompare(clampedTime, endTime) < 0 {
        return (
          segment.clipIndex,
          CMTimeSubtract(clampedTime, segment.startTime)
        )
      }
    }

    let lastSegment = segments[segments.count - 1]
    return (lastSegment.clipIndex, lastSegment.duration)
  }

  var clipDurationsMs: [Int64] {
    return segments.map { Int64((CMTimeGetSeconds($0.duration) * 1_000).rounded()) }
  }

  func dispose() {
    for url in generatedImageVideoURLs {
      try? FileManager.default.removeItem(at: url)
    }
    generatedImageVideoURLs.removeAll()
    imageVideoCache.removeAll()
  }

  // MARK: - Private

  private func makeVideoComposition() -> AVMutableVideoComposition {
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = renderSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    let instructions = segments.map { segment in
      singleLayerInstruction(
        for: segment,
        start: segment.startTime,
        duration: segment.duration
      )
    }

    videoComposition.instructions = instructions.sorted {
      CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
    }
    return videoComposition
  }

  private func singleLayerInstruction(
    for segment: TimelineSegment,
    start: CMTime,
    duration: CMTime
  ) -> AVMutableVideoCompositionInstruction {
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: start, duration: duration)
    let layerInstruction = layerInstruction(for: segment, at: start)
    layerInstruction.setOpacity(1, at: start)
    instruction.layerInstructions = [layerInstruction]
    return instruction
  }

  private func layerInstruction(
    for segment: TimelineSegment,
    at time: CMTime
  ) -> AVMutableVideoCompositionLayerInstruction {
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(
      assetTrack: segment.videoTrack
    )
    layerInstruction.setTransform(transform(for: segment), at: time)
    return layerInstruction
  }

  private func makeAudioMix() -> AVAudioMix? {
    var parametersByTrackId: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

    for segment in segments {
      guard let audioTrack = segment.audioTrack else {
        continue
      }

      let parameters = parametersByTrackId[audioTrack.trackID] ??
        AVMutableAudioMixInputParameters(track: audioTrack)
      parameters.setVolume(1, at: segment.startTime)
      parametersByTrackId[audioTrack.trackID] = parameters
    }

    guard !parametersByTrackId.isEmpty else {
      return nil
    }

    let mix = AVMutableAudioMix()
    mix.inputParameters = Array(parametersByTrackId.values)
    return mix
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

  private func renderSize(
    for config: TimelineCompositionConfig,
    firstRenderableSize: CGSize
  ) -> CGSize {
    let baseWidth = CGFloat(max(config.baseWidth, 1))
    switch config.aspectRatio {
    case .ratio16x9:
      return evenSize(CGSize(width: baseWidth, height: baseWidth * 9 / 16))
    case .ratio9x16:
      return evenSize(CGSize(width: baseWidth * 9 / 16, height: baseWidth))
    case .ratio1x1:
      return evenSize(CGSize(width: baseWidth, height: baseWidth))
    case .original:
      return evenSize(firstRenderableSize)
    }
  }

  /// Returns the source `AVURLAsset` for a clip, generating a temporary MP4 for images.
  private func resolvedAsset(for clip: TimelineClipDescriptor) throws -> AVURLAsset {
    if clip.type == .video {
      return AVURLAsset(url: URL(fileURLWithPath: clip.path))
    }

    // For images, use cached MP4 if the path hasn't changed
    if let cachedURL = imageVideoCache[clip.path],
       FileManager.default.fileExists(atPath: cachedURL.path) {
      return AVURLAsset(url: cachedURL)
    }

    guard let image = UIImage(contentsOfFile: clip.path) else {
      throw TimelineCompositionError.invalidClip
    }

    let duration = cmTime(fromMilliseconds: clip.durationMs ?? 2_000)
    let url = try makeImageVideo(from: image, duration: duration)
    generatedImageVideoURLs.append(url)
    imageVideoCache[clip.path] = url
    return AVURLAsset(url: url)
  }

  /// Computes the (sourceStart, effectiveDuration) for a clip given trim fields.
  private func effectiveRange(
    for clip: TimelineClipDescriptor,
    asset: AVURLAsset
  ) -> (start: CMTime, duration: CMTime) {
    // Image clips ignore trim; use durationMs or fallback
    if clip.type == .image {
      let dur = cmTime(fromMilliseconds: clip.durationMs ?? 2_000)
      return (.zero, dur)
    }

    let trimStart: CMTime
    if let trimStartMs = clip.trimStartMs, trimStartMs > 0 {
      trimStart = cmTime(fromMilliseconds: trimStartMs)
    } else {
      trimStart = .zero
    }

    let assetDuration = asset.duration.isNumeric ? asset.duration : .zero

    if let trimEndMs = clip.trimEndMs {
      let trimEnd = cmTime(fromMilliseconds: trimEndMs)
      let rawDuration = CMTimeSubtract(trimEnd, trimStart)
      let clampedDuration = CMTimeMinimum(rawDuration, CMTimeSubtract(assetDuration, trimStart))
      return (trimStart, isPositive(clampedDuration) ? clampedDuration : cmTime(fromMilliseconds: 100))
    }

    if let durationMs = clip.durationMs {
      let requested = cmTime(fromMilliseconds: durationMs)
      let available = CMTimeSubtract(assetDuration, trimStart)
      return (trimStart, isPositive(available) ? CMTimeMinimum(requested, available) : requested)
    }

    let available = CMTimeSubtract(assetDuration, trimStart)
    if isPositive(available) {
      return (trimStart, available)
    }

    return (trimStart, cmTime(fromMilliseconds: 2_000))
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

    // CGContext manual tem origem bottom-left; UIImage espera top-left.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)

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

  private func isPositive(_ time: CMTime) -> Bool {
    return time.isNumeric && CMTimeCompare(time, .zero) > 0
  }
}
