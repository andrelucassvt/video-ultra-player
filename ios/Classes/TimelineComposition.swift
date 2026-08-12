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
  /// Playback speed multiplier in the range [0.5, 2.0]. Default 1.0 (normal speed).
  var speed: Double
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
    let speedValue = (dictionary["speed"] as? NSNumber)?.doubleValue ?? 1.0

    self.path = path
    self.type = type
    self.durationMs = durationValue?.int64Value
    self.alignmentX = CGFloat((alignment?["x"] as? NSNumber)?.doubleValue ?? 0)
    self.alignmentY = CGFloat((alignment?["y"] as? NSNumber)?.doubleValue ?? 0)
    self.scale = max(CGFloat(scaleValue?.doubleValue ?? 1), 0.01)
    self.speed = min(max(speedValue, 0.5), 2.0)
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

/// Describes an external audio track overlaid on the timeline.
struct AudioTrackDescriptor {
  let path: String
  let offsetMs: Int64
  let volume: Float
  let trimStartMs: Int64?
  let trimEndMs: Int64?
  let fadeInMs: Int64?
  let fadeOutMs: Int64?

  init?(dictionary: [String: Any]) {
    guard let path = dictionary["path"] as? String else {
      return nil
    }
    self.path = path
    self.offsetMs = (dictionary["offsetMs"] as? NSNumber)?.int64Value ?? 0
    self.volume = (dictionary["volume"] as? NSNumber)?.floatValue ?? 1.0
    self.trimStartMs = (dictionary["trimStartMs"] as? NSNumber)?.int64Value
    self.trimEndMs = (dictionary["trimEndMs"] as? NSNumber)?.int64Value
    self.fadeInMs = (dictionary["fadeInMs"] as? NSNumber)?.int64Value
    self.fadeOutMs = (dictionary["fadeOutMs"] as? NSNumber)?.int64Value
  }
}

/// Horizontal alignment of a multi-line text overlay.
enum TextOverlayTextAlign: String {
  case left
  case center
  case right
}

/// Describes a text overlay burned into the composed video, identical in the
/// preview and the exported MP4.
struct TextOverlayDescriptor {
  let id: String
  let text: String
  let startMs: Int64
  let endMs: Int64
  let x: CGFloat
  let y: CGFloat
  let rotationDegrees: Double
  let fontSize: CGFloat
  let color: UInt32
  let fontFamily: String?
  let fontPath: String?
  let backgroundColor: UInt32
  let opacity: Double
  let textAlign: TextOverlayTextAlign

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? String,
          let text = dictionary["text"] as? String
    else {
      return nil
    }
    let alignValue = dictionary["textAlign"] as? String ?? "center"

    self.id = id
    self.text = text
    self.startMs = (dictionary["startMs"] as? NSNumber)?.int64Value ?? 0
    self.endMs = (dictionary["endMs"] as? NSNumber)?.int64Value ?? 0
    self.x = CGFloat(min(max((dictionary["x"] as? NSNumber)?.doubleValue ?? 0.5, 0), 1))
    self.y = CGFloat(min(max((dictionary["y"] as? NSNumber)?.doubleValue ?? 0.5, 0), 1))
    self.rotationDegrees = (dictionary["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0
    self.fontSize = CGFloat(
      min(max((dictionary["fontSize"] as? NSNumber)?.doubleValue ?? 0.05, 0.01), 1)
    )
    self.color = (dictionary["color"] as? NSNumber)?.uint32Value ?? 0xFFFFFFFF
    self.fontFamily = dictionary["fontFamily"] as? String
    self.fontPath = dictionary["fontPath"] as? String
    self.backgroundColor = (dictionary["backgroundColor"] as? NSNumber)?.uint32Value ?? 0x00000000
    self.opacity = min(max((dictionary["opacity"] as? NSNumber)?.doubleValue ?? 1, 0), 1)
    self.textAlign = TextOverlayTextAlign(rawValue: alignValue) ?? .center
  }
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
  private var renderSize = CGSize(width: 1280, height: 720)
  /// Renderable size of the first clip, kept so `.original` can be resolved on
  /// a config change without re-reading the source tracks.
  private var firstRenderableSize = CGSize(width: 1280, height: 720)
  private var audioMix: AVAudioMix?
  /// Currently set external audio track descriptor (nil = no external audio).
  private(set) var currentAudioTrack: AudioTrackDescriptor?
  /// Text overlays burned into the rendered video.
  private(set) var textOverlays: [TextOverlayDescriptor] = []
  /// Caption cues rendered on top of the video (nil style = no captions).
  private(set) var captionCues: [CaptionCueDescriptor] = []
  private(set) var captionStyle: CaptionStyleDescriptor?

  private(set) var totalDuration = CMTime.zero

  /// Output size used by both the AVPlayer video composition and the text
  /// renderer that burns overlays into the Flutter texture frames.
  var outputRenderSize: CGSize { renderSize }

  // MARK: - Build

  func build(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig = TimelineCompositionConfig(),
    audioTrack: AudioTrackDescriptor? = nil
  ) throws -> AVPlayerItem {
    guard !clips.isEmpty else {
      throw TimelineCompositionError.emptyClips
    }

    self.clips = clips
    if let audioTrack { self.currentAudioTrack = audioTrack }
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

    let hasAnyClipAudio = preparedClips.contains { $0.audioTrack != nil }
    let audioTrack: AVMutableCompositionTrack? = hasAnyClipAudio
      ? mutableComposition.addMutableTrack(
          withMediaType: .audio,
          preferredTrackID: kCMPersistentTrackID_Invalid
        )
      : nil

    firstRenderableSize = preparedClips.first?.renderableSize ?? renderSize
    renderSize = renderSize(for: config, firstRenderableSize: firstRenderableSize)

    var startTime = CMTime.zero
    for (index, prepared) in preparedClips.enumerated() {
      let clip = clips[index]
      let speed = max(clip.speed, 0.5)
      let sourceRange = CMTimeRange(start: prepared.sourceStart, duration: prepared.duration)
      try videoTrack.insertTimeRange(sourceRange, of: prepared.videoTrack, at: startTime)

      // Scale the inserted video segment to achieve the desired playback speed.
      // scaleTimeRange operates on composition-track time (from startTime),
      // shrinking or stretching the media to fit the scaled duration.
      let scaledVideoDuration = CMTimeMultiplyByFloat64(prepared.duration, multiplier: 1.0 / speed)
      let compositionVideoRange = CMTimeRange(start: startTime, duration: prepared.duration)
      videoTrack.scaleTimeRange(compositionVideoRange, toDuration: scaledVideoDuration)

      if let sourceAudioTrack = prepared.audioTrack, let audioTrack {
        let maxAudioDuration = CMTimeSubtract(prepared.asset.duration, prepared.sourceStart)
        let audioDuration = CMTimeMinimum(prepared.duration, maxAudioDuration)
        if isPositive(audioDuration) {
          try audioTrack.insertTimeRange(
            CMTimeRange(start: prepared.sourceStart, duration: audioDuration),
            of: sourceAudioTrack,
            at: startTime
          )
          // Scale audio independently — its source duration may differ from video.
          let scaledAudioDuration = CMTimeMultiplyByFloat64(audioDuration, multiplier: 1.0 / speed)
          let compositionAudioRange = CMTimeRange(start: startTime, duration: audioDuration)
          audioTrack.scaleTimeRange(compositionAudioRange, toDuration: scaledAudioDuration)
        }
      }

      // TimelineSegment uses the scaled (display) duration so that totalDuration,
      // seekToClip, clipDurationsMs, and playbackState all stay correct.
      segments.append(
        TimelineSegment(
          clipIndex: index,
          startTime: startTime,
          duration: scaledVideoDuration,
          naturalSize: prepared.naturalSize,
          preferredTransform: prepared.preferredTransform,
          videoTrack: videoTrack,
          audioTrack: audioTrack
        )
      )
      startTime = CMTimeAdd(startTime, scaledVideoDuration)
    }

    totalDuration = startTime

    // Insert external audio track (if set) as a separate composition track.
    var externalAudioCompositionTrack: AVCompositionTrack? = nil
    if let extTrack = currentAudioTrack {
      let extAudioAsset = AVURLAsset(url: URL(fileURLWithPath: extTrack.path))
      if let sourceAudioTrack = extAudioAsset.tracks(withMediaType: .audio).first,
         let extTrackMutable = mutableComposition.addMutableTrack(
           withMediaType: .audio,
           preferredTrackID: kCMPersistentTrackID_Invalid
         ) {
        let assetDuration = extAudioAsset.duration.isNumeric
          ? extAudioAsset.duration
          : .zero
        let offsetTime = cmTime(fromMilliseconds: extTrack.offsetMs)
        let sourceStart: CMTime
        if let trimStartMs = extTrack.trimStartMs {
          sourceStart = cmTime(fromMilliseconds: trimStartMs)
        } else {
          sourceStart = .zero
        }
        let sourceDuration: CMTime
        if let trimEndMs = extTrack.trimEndMs {
          let trimEnd = cmTime(fromMilliseconds: trimEndMs)
          let raw = CMTimeSubtract(trimEnd, sourceStart)
          sourceDuration = isPositive(raw) ? raw : assetDuration
        } else {
          let available = CMTimeSubtract(assetDuration, sourceStart)
          sourceDuration = isPositive(available) ? available : assetDuration
        }
        let timelineRemaining = CMTimeSubtract(totalDuration, offsetTime)
        let clampedSourceDuration = CMTimeMinimum(sourceDuration, timelineRemaining)
        if isPositive(clampedSourceDuration) {
          try? extTrackMutable.insertTimeRange(
            CMTimeRange(start: sourceStart, duration: clampedSourceDuration),
            of: sourceAudioTrack,
            at: offsetTime
          )
          externalAudioCompositionTrack = extTrackMutable
        }
      }
    }

    audioMix = makeAudioMix(externalAudioTrack: externalAudioCompositionTrack,
                             externalDescriptor: currentAudioTrack,
                             timelineEnd: totalDuration)
    self.composition = mutableComposition

    let playerItem = AVPlayerItem(asset: mutableComposition)
    // AVVideoCompositionCoreAnimationTool is only supported for offline
    // rendering. Text is composited by TimelineTexture during playback.
    playerItem.videoComposition = makeVideoComposition(includeTextOverlays: false)
    playerItem.audioMix = audioMix
    return playerItem
  }

  /// Rebuilds from the current `clips` list without accepting new clips.
  ///
  /// Pass `clearAudioTrack: true` to rebuild without any external audio track
  /// (used by `removeAudioTrack`).
  func rebuildAsPlayerItem(
    config: TimelineCompositionConfig,
    clearAudioTrack: Bool = false
  ) throws -> AVPlayerItem {
    if clearAudioTrack {
      currentAudioTrack = nil
    }
    return try build(clips: clips, config: config)
  }

  func buildExportAsset(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig = TimelineCompositionConfig()
  ) throws -> TimelineExportAsset {
    let playerItem = try build(clips: clips, config: config)
    return TimelineExportAsset(
      asset: playerItem.asset,
      videoComposition: makeVideoComposition(
        includeTextOverlays: true,
        includeCaptions: true
      ),
      audioMix: playerItem.audioMix
    )
  }

  /// Builds an export asset from the current (edited) clips list, including
  /// any active external audio track.
  func buildCurrentExportAsset(config: TimelineCompositionConfig) throws -> TimelineExportAsset {
    return try buildExportAsset(clips: clips, config: config)
  }

  /// Sets the external audio track and marks it as current for subsequent
  /// rebuild calls. Does NOT trigger a rebuild — the caller is responsible.
  func setAudioTrack(_ descriptor: AudioTrackDescriptor) {
    currentAudioTrack = descriptor
  }

  /// Clears the external audio track. Does NOT trigger a rebuild.
  func clearAudioTrack() {
    currentAudioTrack = nil
  }

  /// Adds a text overlay. Does NOT trigger a rebuild — the caller is
  /// responsible for regenerating the video composition.
  func addTextOverlay(_ descriptor: TextOverlayDescriptor) {
    textOverlays.append(descriptor)
  }

  /// Replaces the text overlay with the same `id` (no-op when it does not
  /// exist). Does NOT trigger a rebuild.
  func updateTextOverlay(_ descriptor: TextOverlayDescriptor) {
    guard let index = textOverlays.firstIndex(where: { $0.id == descriptor.id }) else {
      return
    }
    textOverlays[index] = descriptor
  }

  /// Removes the text overlay with the given `id` (no-op when it does not
  /// exist). Does NOT trigger a rebuild.
  func removeTextOverlay(id: String) {
    textOverlays.removeAll { $0.id == id }
  }

  /// Replaces the caption cues and style. Does NOT trigger a rebuild — the
  /// caller is responsible for regenerating the video composition.
  func setCaptions(_ cues: [CaptionCueDescriptor], style: CaptionStyleDescriptor) {
    captionCues = cues
    captionStyle = style
  }

  /// Removes the captions previously set via `setCaptions`. Does NOT trigger
  /// a rebuild.
  func removeCaptions() {
    captionCues = []
    captionStyle = nil
  }

  var hasCaptions: Bool {
    return !captionCues.isEmpty && captionStyle != nil
  }

  func makeEditSnapshot() -> TimelineEditSnapshot {
    return TimelineEditSnapshot(
      clips: clips,
      audioTrack: currentAudioTrack,
      textOverlays: textOverlays,
      captionCues: captionCues,
      captionStyle: captionStyle
    )
  }

  func restoreEditSnapshot(_ snapshot: TimelineEditSnapshot) {
    clips = snapshot.clips
    currentAudioTrack = snapshot.audioTrack
    textOverlays = snapshot.textOverlays
    captionCues = snapshot.captionCues
    captionStyle = snapshot.captionStyle
  }

  var clipCount: Int {
    return clips.count
  }

  var hasAudioTrack: Bool {
    return currentAudioTrack != nil
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

  /// Updates the speed of the clip at `index` and marks the composition dirty.
  ///
  /// The caller must call `rebuildAsPlayerItem(config:)` afterwards to apply
  /// the change to the active `AVPlayer`.
  func setClipSpeed(at index: Int, speed: Double) {
    guard clips.indices.contains(index) else { return }
    clips[index].speed = min(max(speed, 0.5), 2.0)
  }

  // MARK: - Queries

  func updateAlignment(clipIndex: Int, x: CGFloat, y: CGFloat) -> AVVideoComposition? {
    guard clips.indices.contains(clipIndex), composition != nil else {
      return nil
    }

    clips[clipIndex].alignmentX = min(max(x, -1), 1)
    clips[clipIndex].alignmentY = min(max(y, -1), 1)
    return makeVideoComposition(includeTextOverlays: false)
  }

  func startTime(forClipIndex clipIndex: Int) -> CMTime? {
    return segments.first(where: { $0.clipIndex == clipIndex })?.startTime
  }

  /// Regenerates a composition that is safe to assign to AVPlayerItem.
  /// Text overlays are deliberately excluded because CoreAnimationTool is
  /// supported only by offline renderers such as AVAssetExportSession.
  func updatedVideoComposition() -> AVVideoComposition {
    return makeVideoComposition(includeTextOverlays: false)
  }

  /// Applies a new output resolution/aspect ratio without touching the
  /// underlying `AVMutableComposition`.
  ///
  /// Only the render size and the per-segment transforms depend on the config,
  /// so the source tracks stay loaded and no clip is re-decoded. Returns the
  /// regenerated video composition, or `nil` when the size is unchanged or the
  /// timeline has not been built yet.
  func updateConfig(_ config: TimelineCompositionConfig) -> AVVideoComposition? {
    guard composition != nil else { return nil }
    let nextSize = renderSize(for: config, firstRenderableSize: firstRenderableSize)
    guard nextSize != renderSize else { return nil }
    renderSize = nextSize
    return makeVideoComposition(includeTextOverlays: false)
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

  /// Image renders live in the shared `ImageClipVideoCache`, which outlives
  /// individual compositions — there is nothing per-instance left to release.
  func dispose() {}

  // MARK: - Private

  private func makeVideoComposition(
    includeTextOverlays: Bool,
    includeCaptions: Bool = false
  ) -> AVMutableVideoComposition {
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

    let hasText = includeTextOverlays && !textOverlays.isEmpty
    let hasCaptions = includeCaptions && hasCaptionsState
    if (hasText || hasCaptions),
       let composition {
      // The post-processing Core Animation initializer crashes in several
      // iOS Simulator runtimes while bridging its output through IOSurface.
      // Model the overlay as a synthetic composition input instead. Each
      // instruction references that track before the video track, preserving
      // z-order without invoking the failing post-processing path.
      let overlayTrackID = composition.unusedTrackID()
      let overlayLayer = makeOverlayParentLayer(
        includeTextOverlays: hasText,
        includeCaptions: hasCaptions
      )
      videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        additionalLayer: overlayLayer,
        asTrackID: overlayTrackID
      )

      TextOverlayLayers.prependOverlayTrack(overlayTrackID, to: instructions)
    }

    videoComposition.instructions = instructions.sorted {
      CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
    }

    return videoComposition
  }

  private var hasCaptionsState: Bool {
    return !captionCues.isEmpty && captionStyle != nil
  }

  /// Builds the root Core Animation layer for export: text overlay layers
  /// first, caption layers on top of them.
  private func makeOverlayParentLayer(
    includeTextOverlays: Bool,
    includeCaptions: Bool
  ) -> CALayer {
    if includeTextOverlays && includeCaptions {
      let root = CALayer()
      root.frame = CGRect(origin: .zero, size: renderSize)
      root.isGeometryFlipped = true
      root.addSublayer(
        TextOverlayLayers.makeTextOverlayParentLayer(
          overlays: textOverlays,
          renderSize: renderSize,
          totalDuration: totalDuration
        )
      )
      if let captionStyle {
        root.addSublayer(
          CaptionLayers.makeCaptionParentLayer(
            cues: captionCues,
            style: captionStyle,
            renderSize: renderSize,
            totalDuration: totalDuration
          )
        )
      }
      return root
    }
    if includeCaptions, let captionStyle {
      return CaptionLayers.makeCaptionParentLayer(
        cues: captionCues,
        style: captionStyle,
        renderSize: renderSize,
        totalDuration: totalDuration
      )
    }
    return TextOverlayLayers.makeTextOverlayParentLayer(
      overlays: textOverlays,
      renderSize: renderSize,
      totalDuration: totalDuration
    )
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

  private func makeAudioMix(
    externalAudioTrack: AVCompositionTrack? = nil,
    externalDescriptor: AudioTrackDescriptor? = nil,
    timelineEnd: CMTime = .zero
  ) -> AVAudioMix? {
    var parametersByTrackId: [CMPersistentTrackID: AVMutableAudioMixInputParameters] = [:]

    // Clip audio tracks — set full volume at each segment's start time.
    for segment in segments {
      guard let audioTrack = segment.audioTrack else {
        continue
      }

      let parameters = parametersByTrackId[audioTrack.trackID] ??
        AVMutableAudioMixInputParameters(track: audioTrack)
      parameters.setVolume(1, at: segment.startTime)
      parametersByTrackId[audioTrack.trackID] = parameters
    }

    // External audio track — apply volume, fade-in, and fade-out ramps.
    if let extTrack = externalAudioTrack, let descriptor = externalDescriptor {
      let parameters = AVMutableAudioMixInputParameters(track: extTrack)
      let volume = descriptor.volume.isNaN ? 1.0 : max(0, min(descriptor.volume, 1))
      let offsetTime = cmTime(fromMilliseconds: descriptor.offsetMs)

      // Determine the end of the external audio region in composition time.
      var extDuration: CMTime
      if let trimEndMs = descriptor.trimEndMs {
        let trimEnd = cmTime(fromMilliseconds: trimEndMs)
        let trimStart = descriptor.trimStartMs.map { cmTime(fromMilliseconds: $0) } ?? .zero
        extDuration = CMTimeSubtract(trimEnd, trimStart)
      } else {
        // Duration is whatever fits before the timeline end.
        extDuration = CMTimeSubtract(timelineEnd, offsetTime)
      }
      let timelineRemaining = CMTimeSubtract(timelineEnd, offsetTime)
      extDuration = CMTimeMinimum(extDuration, timelineRemaining)
      let extEnd = CMTimeAdd(offsetTime, isPositive(extDuration) ? extDuration : .zero)

      if let fadeInMs = descriptor.fadeInMs, fadeInMs > 0 {
        let fadeInDuration = cmTime(fromMilliseconds: fadeInMs)
        parameters.setVolumeRamp(
          fromStartVolume: 0,
          toEndVolume: volume,
          timeRange: CMTimeRange(start: offsetTime, duration: fadeInDuration)
        )
        // Hold volume after fade-in
        let afterFadeIn = CMTimeAdd(offsetTime, fadeInDuration)
        parameters.setVolume(volume, at: afterFadeIn)
      } else {
        parameters.setVolume(volume, at: offsetTime)
      }

      if let fadeOutMs = descriptor.fadeOutMs, fadeOutMs > 0, isPositive(extEnd) {
        let fadeOutDuration = cmTime(fromMilliseconds: fadeOutMs)
        let fadeOutStart = CMTimeSubtract(extEnd, fadeOutDuration)
        if isPositive(fadeOutStart) {
          parameters.setVolumeRamp(
            fromStartVolume: volume,
            toEndVolume: 0,
            timeRange: CMTimeRange(start: fadeOutStart, duration: fadeOutDuration)
          )
        }
      }

      parametersByTrackId[extTrack.trackID] = parameters
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
  ///
  /// Image renders come from the process-wide `ImageClipVideoCache`, so a
  /// rebuild (or a second timeline using the same still) never re-encodes.
  private func resolvedAsset(for clip: TimelineClipDescriptor) throws -> AVURLAsset {
    if clip.type == .video {
      return AVURLAsset(url: URL(fileURLWithPath: clip.path))
    }

    let url = try ImageClipVideoCache.shared.videoURL(
      forImageAt: clip.path,
      durationMs: clip.durationMs ?? 2_000
    )
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
