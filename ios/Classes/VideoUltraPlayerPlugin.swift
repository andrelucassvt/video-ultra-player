import Flutter
import AVFoundation
import UIKit

public class VideoUltraPlayerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "video_ultra_player/timeline_player"
  private static let eventChannelName = "video_ultra_player/timeline_player/events"
  private static let exportEventChannelName = "video_ultra_player/timeline_player/export"

  private let textureRegistry: FlutterTextureRegistry?
  private var controllers: [Int64: TimelinePlayerController] = [:]
  private let exportProgressHandler = TimelineExportProgressStreamHandler()

  public override init() {
    textureRegistry = nil
    super.init()
  }

  init(textureRegistry: FlutterTextureRegistry?) {
    self.textureRegistry = textureRegistry
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VideoUltraPlayerPlugin(textureRegistry: registrar.textures())
    let channel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    let exportEventChannel = FlutterEventChannel(
      name: exportEventChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    eventChannel.setStreamHandler(instance)
    exportEventChannel.setStreamHandler(instance.exportProgressHandler)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "load":
      load(call, result: result)
    case "exportTimeline":
      exportTimeline(call, result: result)
    case "exportCurrentTimeline":
      exportCurrentTimeline(call, result: result)
    case "play":
      guard let controller = controller(for: call, result: result) else { return }
      controller.play()
      result(nil)
    case "pause":
      guard let controller = controller(for: call, result: result) else { return }
      controller.pause()
      result(nil)
    case "seekTo":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let positionMs = args["positionMs"] as? NSNumber
      else { return }
      controller.seek(toMilliseconds: positionMs.int64Value)
      result(nil)
    case "seekToClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber
      else { return }
      controller.seekToClip(clipIndex: clipIndex.intValue)
      result(nil)
    case "setVolume":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let volume = args["volume"] as? NSNumber
      else { return }
      controller.setVolume(volume.floatValue)
      result(nil)
    case "setClipAlignment":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber,
            let x = args["x"] as? NSNumber,
            let y = args["y"] as? NSNumber
      else { return }
      controller.setClipAlignment(
        clipIndex: clipIndex.intValue,
        x: CGFloat(x.doubleValue),
        y: CGFloat(y.doubleValue)
      )
      result(nil)
    case "setCompositionConfig":
      guard let controller = controller(for: call, result: result) else { return }
      controller.setCompositionConfig(compositionConfig(from: call.arguments))
      result(nil)
    case "trimClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber
      else { return }
      let trimStartMs = (args["trimStartMs"] as? NSNumber)?.int64Value
      let trimEndMs = (args["trimEndMs"] as? NSNumber)?.int64Value
      do {
        try controller.trimClip(at: clipIndex.intValue, trimStartMs: trimStartMs, trimEndMs: trimEndMs)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "trimClip failed", details: "\(error)"))
      }
    case "splitClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber,
            let atLocalPositionMs = args["atLocalPositionMs"] as? NSNumber
      else { return }
      do {
        try controller.splitClip(at: clipIndex.intValue, atLocalMs: atLocalPositionMs.int64Value)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "splitClip failed", details: "\(error)"))
      }
    case "insertClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipDict = args["clip"] as? [String: Any],
            let clip = TimelineClipDescriptor(dictionary: clipDict),
            let atIndex = args["atIndex"] as? NSNumber
      else { return }
      do {
        try controller.insertClip(clip, at: atIndex.intValue)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "insertClip failed", details: "\(error)"))
      }
    case "removeClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber
      else { return }
      do {
        try controller.removeClip(at: clipIndex.intValue)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "removeClip failed", details: "\(error)"))
      }
    case "moveClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let fromIndex = args["fromIndex"] as? NSNumber,
            let toIndex = args["toIndex"] as? NSNumber
      else { return }
      do {
        try controller.moveClip(from: fromIndex.intValue, to: toIndex.intValue)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "moveClip failed", details: "\(error)"))
      }
    case "replaceClip":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber,
            let clipDict = args["clip"] as? [String: Any],
            let clip = TimelineClipDescriptor(dictionary: clipDict)
      else { return }
      do {
        try controller.replaceClip(at: clipIndex.intValue, with: clip)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "replaceClip failed", details: "\(error)"))
      }
    case "setClipSpeed":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let clipIndex = args["clipIndex"] as? NSNumber,
            let speed = args["speed"] as? NSNumber
      else { return }
      do {
        try controller.setClipSpeed(at: clipIndex.intValue, speed: speed.doubleValue)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "setClipSpeed failed", details: "\(error)"))
      }
    case "undo":
      guard let controller = controller(for: call, result: result) else { return }
      do {
        try controller.undo()
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "undo failed", details: "\(error)"))
      }
    case "redo":
      guard let controller = controller(for: call, result: result) else { return }
      do {
        try controller.redo()
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "redo failed", details: "\(error)"))
      }
    case "setAudioTrack":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any],
            let trackDict = args["track"] as? [String: Any],
            let descriptor = AudioTrackDescriptor(dictionary: trackDict)
      else { return }
      do {
        try controller.setAudioTrack(descriptor)
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "setAudioTrack failed", details: "\(error)"))
      }
    case "removeAudioTrack":
      guard let controller = controller(for: call, result: result) else { return }
      do {
        try controller.removeAudioTrack()
        result(nil)
      } catch {
        result(FlutterError(code: "edit_failed", message: "removeAudioTrack failed", details: "\(error)"))
      }
    case "addTextOverlay":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any]
      else { return }
      guard let overlayDict = args["overlay"] as? [String: Any],
            let descriptor = TextOverlayDescriptor(dictionary: overlayDict) else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "addTextOverlay requires a valid overlay map.",
          details: nil
        ))
        return
      }
      controller.addTextOverlay(descriptor)
      result(nil)
    case "updateTextOverlay":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any]
      else { return }
      guard let overlayDict = args["overlay"] as? [String: Any],
            let descriptor = TextOverlayDescriptor(dictionary: overlayDict) else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "updateTextOverlay requires a valid overlay map.",
          details: nil
        ))
        return
      }
      controller.updateTextOverlay(descriptor)
      result(nil)
    case "removeTextOverlay":
      guard let controller = controller(for: call, result: result),
            let args = call.arguments as? [String: Any]
      else { return }
      guard let overlayId = args["overlayId"] as? String else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "removeTextOverlay requires overlayId (String).",
          details: nil
        ))
        return
      }
      controller.removeTextOverlay(id: overlayId)
      result(nil)
    case "generateThumbnails":
      guard let args = call.arguments as? [String: Any],
            let videoPath = args["videoPath"] as? String,
            let timestampsMs = args["timestampsMs"] as? [Int],
            let width = args["width"] as? Int else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "generateThumbnails requires videoPath (String), timestampsMs ([Int]), width (Int)",
          details: nil
        ))
        return
      }
      ThumbnailGenerator.shared.generate(
        videoPath: videoPath,
        timestampsMs: timestampsMs,
        width: width
      ) { paths in
        DispatchQueue.main.async {
          result(paths)
        }
      }
    case "dispose":
      guard let textureId = textureId(from: call.arguments, result: result),
            let controller = controllers.removeValue(forKey: textureId)
      else { return }
      controller.dispose()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard let textureId = textureId(from: arguments) else {
      return FlutterError(
        code: "invalid_arguments",
        message: "Expected textureId for timeline state stream.",
        details: nil
      )
    }

    controllers[textureId]?.eventSink = events
    controllers[textureId]?.emitState()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    guard let textureId = textureId(from: arguments) else {
      return nil
    }
    controllers[textureId]?.eventSink = nil
    return nil
  }

  private func load(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let textureRegistry else {
      result(
        FlutterError(
          code: "not_attached",
          message: "VideoUltraPlayerPlugin is not attached to a Flutter texture registry.",
          details: nil
        )
      )
      return
    }

    guard let clips = clips(from: call.arguments, result: result) else { return }
    let config = compositionConfig(from: call.arguments)

    // Composition assembly reads and decodes the sources, so it runs off the
    // platform thread; only texture registration comes back to main.
    TimelinePlayerController.make(
      clips: clips,
      config: config,
      textureRegistry: textureRegistry
    ) { [weak self] outcome in
      switch outcome {
      case .success(let controller):
        guard let self else {
          controller.dispose()
          result(
            FlutterError(
              code: "load_failed",
              message: "Plugin was detached before the timeline finished loading.",
              details: nil
            )
          )
          return
        }
        self.controllers[controller.textureId] = controller
        result(controller.textureId)
      case .failure(let error):
        result(
          FlutterError(
            code: "load_failed",
            message: "Unable to build native timeline composition.",
            details: "\(error)"
          )
        )
      }
    }
  }

  private func exportTimeline(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let clips = clips(from: call.arguments, result: result) else { return }
    let config = compositionConfig(from: call.arguments)
    let outputPath = (call.arguments as? [String: Any])?["outputPath"] as? String
    let outputURL = exportOutputURL(outputPath: outputPath)
    let composition = TimelineComposition()

    do {
      try prepareOutputDirectory(at: outputURL)

      let exportAsset = try composition.buildExportAsset(clips: clips, config: config)
      runExportSession(
        asset: exportAsset,
        outputURL: outputURL,
        onDispose: { composition.dispose() },
        result: result
      )
    } catch {
      composition.dispose()
      exportProgressHandler.emit(progress: 0, state: "failed")
      result(
        FlutterError(
          code: "export_failed",
          message: "Unable to export native timeline composition.",
          details: "\(error)"
        )
      )
    }
  }

  private func exportCurrentTimeline(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let controller = controller(for: call, result: result) else { return }
    let outputPath = (call.arguments as? [String: Any])?["outputPath"] as? String
    let outputURL = exportOutputURL(outputPath: outputPath)

    do {
      try prepareOutputDirectory(at: outputURL)

      let exportAsset = try controller.buildCurrentExportAsset()
      runExportSession(asset: exportAsset, outputURL: outputURL, onDispose: nil, result: result)
    } catch {
      exportProgressHandler.emit(progress: 0, state: "failed")
      result(
        FlutterError(
          code: "export_failed",
          message: "Unable to export current timeline.",
          details: "\(error)"
        )
      )
    }
  }

  private func runExportSession(
    asset: TimelineExportAsset,
    outputURL: URL,
    onDispose: (() -> Void)?,
    result: @escaping FlutterResult
  ) {
    guard
      let exporter = AVAssetExportSession(
        asset: asset.asset,
        presetName: AVAssetExportPresetHighestQuality
      )
    else {
      onDispose?()
      exportProgressHandler.emit(progress: 0, state: "failed")
      result(
        FlutterError(
          code: "export_failed",
          message: "Unable to create export session.",
          details: nil
        )
      )
      return
    }

    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = asset.videoComposition
    exporter.audioMix = asset.audioMix
    exportProgressHandler.emit(progress: 0, state: "exporting")

    let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
      [weak exporter, weak exportProgressHandler] _ in
      guard let exporter else { return }
      exportProgressHandler?.emit(progress: Double(exporter.progress), state: "exporting")
    }

    exporter.exportAsynchronously {
      DispatchQueue.main.async {
        progressTimer.invalidate()
        onDispose?()
        switch exporter.status {
        case .completed:
          self.exportProgressHandler.emit(progress: 1, state: "completed")
          result(outputURL.path)
        case .failed, .cancelled:
          self.exportProgressHandler.emit(progress: Double(exporter.progress), state: "failed")
          result(
            FlutterError(
              code: "export_failed",
              message: "Export failed or was cancelled.",
              details: exporter.error?.localizedDescription
            )
          )
        default:
          self.exportProgressHandler.emit(progress: Double(exporter.progress), state: "failed")
          result(
            FlutterError(
              code: "export_failed",
              message: "Timeline export ended in unexpected state.",
              details: "\(exporter.status.rawValue)"
            )
          )
        }
      }
    }
  }

  private func prepareOutputDirectory(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private func clips(from arguments: Any?, result: FlutterResult) -> [TimelineClipDescriptor]? {
    guard
      let args = arguments as? [String: Any],
      let rawClips = args["clips"] as? [[String: Any]]
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Expected clips list.",
          details: nil
        )
      )
      return nil
    }

    let clips = rawClips.compactMap(TimelineClipDescriptor.init(dictionary:))
    guard clips.count == rawClips.count else {
      result(
        FlutterError(
          code: "invalid_clip",
          message: "One or more timeline clips are invalid.",
          details: nil
        )
      )
      return nil
    }
    return clips
  }

  private func compositionConfig(from arguments: Any?) -> TimelineCompositionConfig {
    let args = arguments as? [String: Any]
    return TimelineCompositionConfig(dictionary: args?["config"] as? [String: Any])
  }

  private func exportOutputURL(outputPath: String?) -> URL {
    if let outputPath, !outputPath.isEmpty {
      return URL(fileURLWithPath: outputPath)
    }

    return FileManager.default.temporaryDirectory.appendingPathComponent(
      "video_ultra_player_export_\(UUID().uuidString).mp4"
    )
  }

  private func controller(
    for call: FlutterMethodCall,
    result: FlutterResult
  ) -> TimelinePlayerController? {
    guard let textureId = textureId(from: call.arguments, result: result) else {
      return nil
    }

    guard let controller = controllers[textureId] else {
      result(
        FlutterError(
          code: "not_found",
          message: "No native timeline player exists for textureId \(textureId).",
          details: nil
        )
      )
      return nil
    }
    return controller
  }

  private func textureId(from arguments: Any?, result: FlutterResult) -> Int64? {
    guard let textureId = textureId(from: arguments) else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Expected textureId.",
          details: nil
        )
      )
      return nil
    }
    return textureId
  }

  private func textureId(from arguments: Any?) -> Int64? {
    guard
      let args = arguments as? [String: Any],
      let value = args["textureId"] as? NSNumber
    else {
      return nil
    }
    return value.int64Value
  }
}

private final class TimelinePlayerController {
  /// Serial queue where compositions are assembled. Reading source tracks and
  /// rendering stills are blocking operations — keeping them off the platform
  /// thread is what stops `load` from freezing the UI.
  private static let buildQueue = DispatchQueue(
    label: "video_ultra_player.timeline.build",
    qos: .userInitiated
  )

  /// Snapshot of everything reported on the state channel, used to suppress
  /// duplicate events (a paused player would otherwise emit 30 identical
  /// messages per second).
  private struct EmittedState: Equatable {
    let globalPosition: Int64
    let clipIndex: Int
    let localPosition: Int64
    let isPlaying: Bool
    let totalDuration: Int64
    let clipDurations: [Int64]
    let canUndo: Bool
    let canRedo: Bool
  }

  let textureId: Int64
  var eventSink: FlutterEventSink? {
    didSet { lastEmittedState = nil }
  }

  private let composition: TimelineComposition
  private let player: AVPlayer
  private let texture: TimelineTexture
  private let textureRegistry: FlutterTextureRegistry
  private let editHistory = TimelineEditModel()
  private var timeObserver: Any?
  private var currentConfig: TimelineCompositionConfig
  private var lastEmittedState: EmittedState?
  /// One-shot observer that forces the first frame once the initial item is ready.
  private var firstFrameObserver: NSKeyValueObservation?

  /// Builds the composition off the platform thread and hands back a ready
  /// controller on the main thread, where texture registration must happen.
  static func make(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig,
    textureRegistry: FlutterTextureRegistry,
    completion: @escaping (Result<TimelinePlayerController, Error>) -> Void
  ) {
    buildQueue.async {
      let composition = TimelineComposition()
      do {
        let playerItem = try composition.build(clips: clips, config: config)
        DispatchQueue.main.async {
          completion(
            .success(
              TimelinePlayerController(
                composition: composition,
                playerItem: playerItem,
                config: config,
                textureRegistry: textureRegistry
              )
            )
          )
        }
      } catch {
        composition.dispose()
        DispatchQueue.main.async {
          completion(.failure(error))
        }
      }
    }
  }

  private init(
    composition: TimelineComposition,
    playerItem: AVPlayerItem,
    config: TimelineCompositionConfig,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.composition = composition
    self.textureRegistry = textureRegistry
    self.currentConfig = config
    // Attach the video output to the item BEFORE handing it to AVPlayer so
    // the output is part of the rendering pipeline from the very first frame.
    let tex = TimelineTexture(playerItem: playerItem, textureRegistry: textureRegistry)
    player = AVPlayer(playerItem: playerItem)
    texture = tex
    textureId = textureRegistry.register(tex)
    tex.textureId = textureId
    tex.start()
    addObservers()
    observeInitialItemReady(playerItem)
  }

  // MARK: - Playback

  func play() {
    player.play()
    emitState()
  }

  func pause() {
    player.pause()
    emitState()
  }

  func seek(toMilliseconds positionMs: Int64) {
    let position = CMTime(value: max(positionMs, 0), timescale: 1_000)
    player.seek(
      to: position,
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      self?.emitState()
    }
  }

  func seekToClip(clipIndex: Int) {
    guard let startTime = composition.startTime(forClipIndex: clipIndex) else {
      return
    }
    player.seek(
      to: startTime,
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      self?.emitState()
    }
  }

  func setVolume(_ volume: Float) {
    player.volume = min(max(volume, 0), 1)
    emitState()
  }

  func setClipAlignment(clipIndex: Int, x: CGFloat, y: CGFloat) {
    guard clipIndex >= 0, clipIndex < composition.clipCount else {
      return
    }
    pushEditSnapshot()
    guard let videoComposition = composition.updateAlignment(
      clipIndex: clipIndex,
      x: x,
      y: y
    ) else {
      return
    }
    player.currentItem?.videoComposition = videoComposition
    emitState()
  }

  /// Switches output resolution/aspect ratio in place.
  ///
  /// The `AVMutableComposition` (and therefore every decoded source) is left
  /// untouched — only the video composition is regenerated and reassigned, the
  /// same surgical path used for text-overlay mutations. Clips, overlays, undo
  /// history, texture ID and playback position all survive.
  func setCompositionConfig(_ config: TimelineCompositionConfig) {
    currentConfig = config
    guard let videoComposition = composition.updateConfig(config) else {
      emitState()
      return
    }

    player.currentItem?.videoComposition = videoComposition
    texture.updateTextOverlays(
      composition.textOverlays,
      renderSize: composition.outputRenderSize,
      totalDuration: composition.totalDuration
    )

    if player.rate == 0 {
      let time = player.currentTime()
      player.seek(
        to: time,
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        self?.texture.requestFrame()
      }
    }
    emitState()
  }

  // MARK: - Editing

  func trimClip(at index: Int, trimStartMs: Int64?, trimEndMs: Int64?) throws {
    guard index >= 0, index < composition.clipCount else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.trimClip(at: index, trimStartMs: trimStartMs, trimEndMs: trimEndMs)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func splitClip(at index: Int, atLocalMs: Int64) throws {
    guard index >= 0, index < composition.clipCount, atLocalMs > 0 else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.splitClip(at: index, atLocalMs: atLocalMs)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func insertClip(_ clip: TimelineClipDescriptor, at index: Int) throws {
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.insertClip(clip, at: index)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func removeClip(at index: Int) throws {
    guard index >= 0, index < composition.clipCount else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.removeClip(at: index)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func moveClip(from: Int, to: Int) throws {
    guard from >= 0, from < composition.clipCount,
          to >= 0, to < composition.clipCount,
          from != to
    else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.moveClip(from: from, to: to)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func replaceClip(at index: Int, with clip: TimelineClipDescriptor) throws {
    guard index >= 0, index < composition.clipCount else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.replaceClip(at: index, with: clip)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func setClipSpeed(at index: Int, speed: Double) throws {
    guard index >= 0, index < composition.clipCount else { return }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.setClipSpeed(at: index, speed: speed)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func setAudioTrack(_ descriptor: AudioTrackDescriptor) throws {
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.setAudioTrack(descriptor)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func removeAudioTrack() throws {
    guard composition.hasAudioTrack else {
      emitState()
      return
    }
    let positionMs = player.currentTime().timelineMilliseconds
    pushEditSnapshot()
    composition.clearAudioTrack()
    try rebuildPreservingPlayback(positionMs: positionMs, clearAudioTrack: true)
  }

  // MARK: - Text overlays

  func addTextOverlay(_ descriptor: TextOverlayDescriptor) {
    pushEditSnapshot()
    composition.addTextOverlay(descriptor)
    applyUpdatedTextOverlays()
  }

  func updateTextOverlay(_ descriptor: TextOverlayDescriptor) {
    pushEditSnapshot()
    composition.updateTextOverlay(descriptor)
    applyUpdatedTextOverlays()
  }

  func removeTextOverlay(id: String) {
    pushEditSnapshot()
    composition.removeTextOverlay(id: id)
    applyUpdatedTextOverlays()
  }

  func undo() throws {
    let current = composition.makeEditSnapshot()
    guard let snapshot = editHistory.undo(current: current) else {
      emitState()
      return
    }
    let positionMs = player.currentTime().timelineMilliseconds
    composition.restoreEditSnapshot(snapshot)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func redo() throws {
    let current = composition.makeEditSnapshot()
    guard let snapshot = editHistory.redo(current: current) else {
      emitState()
      return
    }
    let positionMs = player.currentTime().timelineMilliseconds
    composition.restoreEditSnapshot(snapshot)
    try rebuildPreservingPlayback(positionMs: positionMs)
  }

  func buildCurrentExportAsset() throws -> TimelineExportAsset {
    return try composition.buildCurrentExportAsset(config: currentConfig)
  }

  // MARK: - State

  /// Emits the current playback state, skipping the channel round-trip when
  /// nothing changed since the last emission.
  func emitState() {
    guard let eventSink else {
      return
    }

    let currentTime = player.currentTime()
    let segmentState = composition.playbackState(at: currentTime)
    let state = EmittedState(
      globalPosition: currentTime.timelineMilliseconds,
      clipIndex: segmentState.clipIndex,
      localPosition: segmentState.localPosition.timelineMilliseconds,
      isPlaying: player.rate != 0,
      totalDuration: composition.totalDuration.timelineMilliseconds,
      clipDurations: composition.clipDurationsMs,
      canUndo: editHistory.canUndo,
      canRedo: editHistory.canRedo
    )
    guard state != lastEmittedState else { return }
    lastEmittedState = state

    eventSink([
      "globalPosition": state.globalPosition,
      "clipIndex": state.clipIndex,
      "localPosition": state.localPosition,
      "isPlaying": state.isPlaying,
      "totalDuration": state.totalDuration,
      "clipDurationsMs": state.clipDurations,
      "canUndo": state.canUndo,
      "canRedo": state.canRedo,
    ])
  }

  func dispose() {
    firstFrameObserver = nil
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }
    NotificationCenter.default.removeObserver(self)
    player.pause()
    texture.dispose()
    textureRegistry.unregisterTexture(textureId)
    composition.dispose()
  }

  // MARK: - Private

  private func rebuildPreservingPlayback(
    positionMs: Int64,
    clearAudioTrack: Bool = false
  ) throws {
    let wasPlaying = player.rate != 0
    let newItem = try composition.rebuildAsPlayerItem(
      config: currentConfig,
      clearAudioTrack: clearAudioTrack
    )
    texture.updateTextOverlays(
      composition.textOverlays,
      renderSize: composition.outputRenderSize,
      totalDuration: composition.totalDuration
    )

    NotificationCenter.default.removeObserver(
      self,
      name: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem
    )

    // AVPlayerItemVideoOutput can only belong to one item; adding it to newItem
    // automatically detaches it from the old item.
    texture.replacePlayerItem(newItem)
    player.replaceCurrentItem(with: newItem)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didPlayToEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: newItem
    )

    let position = CMTime(value: max(positionMs, 0), timescale: 1_000)
    player.seek(
      to: position,
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      if wasPlaying { self?.player.play() }
      self?.emitState()
    }
  }

  private func pushEditSnapshot() {
    editHistory.pushSnapshot(composition.makeEditSnapshot())
  }

  /// Refreshes cached text rasters without assigning a CoreAnimationTool to
  /// AVPlayerItem (Apple only supports that tool for offline rendering).
  /// When paused, a zero-tolerance seek requests a fresh source frame so
  /// removed or edited text cannot remain in the cached Flutter texture.
  private func applyUpdatedTextOverlays() {
    texture.updateTextOverlays(
      composition.textOverlays,
      renderSize: composition.outputRenderSize,
      totalDuration: composition.totalDuration
    )
    player.currentItem?.videoComposition = composition.updatedVideoComposition()
    if player.rate == 0 {
      let time = player.currentTime()
      player.seek(
        to: time,
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        self?.texture.requestFrame()
      }
    }
    emitState()
  }

  /// Observes the player item's readiness one time. On iOS, AVPlayer only
  /// pushes a pixel buffer to AVPlayerItemVideoOutput after an explicit seek
  /// or play; without this, the Texture widget stays black while paused.
  private func observeInitialItemReady(_ playerItem: AVPlayerItem) {
    firstFrameObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      guard item.status == .readyToPlay, let self else { return }
      self.firstFrameObserver = nil  // one-shot
      let time = self.player.currentTime()
      self.player.seek(
        to: time,
        toleranceBefore: .zero,
        toleranceAfter: .zero
      ) { [weak self] _ in
        self?.texture.requestFrame()
      }
    }
  }

  private func addObservers() {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 30),
      queue: .main
    ) { [weak self] _ in
      self?.emitState()
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didPlayToEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem
    )
  }

  @objc private func didPlayToEnd() {
    player.pause()
    emitState()
  }
}

private final class TimelineExportProgressStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    events(["progress": 0.0, "state": "idle"])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func emit(progress: Double, state: String) {
    eventSink?([
      "progress": min(max(progress, 0), 1),
      "state": state,
    ])
  }
}

private extension CMTime {
  var timelineMilliseconds: Int64 {
    guard isNumeric else {
      return 0
    }
    return Int64((CMTimeGetSeconds(self) * 1_000).rounded())
  }
}
