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

    do {
      let controller = try TimelinePlayerController(
        clips: clips,
        config: config,
        textureRegistry: textureRegistry
      )
      controllers[controller.textureId] = controller
      result(controller.textureId)
    } catch {
      result(
        FlutterError(
          code: "load_failed",
          message: "Unable to build native timeline composition.",
          details: "\(error)"
        )
      )
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
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }

      let exportAsset = try composition.buildExportAsset(clips: clips, config: config)
      guard
        let exporter = AVAssetExportSession(
          asset: exportAsset.asset,
          presetName: AVAssetExportPresetHighestQuality
        )
      else {
        throw TimelineCompositionError.cannotCreateExporter
      }

      exporter.outputURL = outputURL
      exporter.outputFileType = .mp4
      exporter.shouldOptimizeForNetworkUse = true
      exporter.videoComposition = exportAsset.videoComposition
      exporter.audioMix = exportAsset.audioMix
      exportProgressHandler.emit(progress: 0, state: "exporting")
      let progressTimer = Timer.scheduledTimer(
        withTimeInterval: 0.1,
        repeats: true
      ) { [weak exporter, weak exportProgressHandler] _ in
        guard let exporter else { return }
        exportProgressHandler?.emit(
          progress: Double(exporter.progress),
          state: "exporting"
        )
      }
      exporter.exportAsynchronously {
        DispatchQueue.main.async {
          progressTimer.invalidate()
          composition.dispose()
          switch exporter.status {
          case .completed:
            self.exportProgressHandler.emit(progress: 1, state: "completed")
            result(outputURL.path)
          case .failed, .cancelled:
            self.exportProgressHandler.emit(
              progress: Double(exporter.progress),
              state: "failed"
            )
            result(
              FlutterError(
                code: "export_failed",
                message: "Unable to export native timeline composition.",
                details: exporter.error?.localizedDescription
              )
            )
          default:
            self.exportProgressHandler.emit(
              progress: Double(exporter.progress),
              state: "failed"
            )
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
  let textureId: Int64
  var eventSink: FlutterEventSink?

  private let composition = TimelineComposition()
  private let player: AVPlayer
  private let texture: TimelineTexture
  private let textureRegistry: FlutterTextureRegistry
  private var timeObserver: Any?

  init(
    clips: [TimelineClipDescriptor],
    config: TimelineCompositionConfig,
    textureRegistry: FlutterTextureRegistry
  ) throws {
    self.textureRegistry = textureRegistry
    let playerItem = try composition.build(clips: clips, config: config)
    player = AVPlayer(playerItem: playerItem)
    texture = TimelineTexture(
      playerItem: playerItem,
      textureRegistry: textureRegistry
    )
    textureId = textureRegistry.register(texture)
    texture.textureId = textureId
    texture.start()
    addObservers()
  }

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

  func setVolume(_ volume: Float) {
    player.volume = min(max(volume, 0), 1)
    emitState()
  }

  func setClipAlignment(clipIndex: Int, x: CGFloat, y: CGFloat) {
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

  func emitState() {
    guard let eventSink else {
      return
    }

    let currentTime = player.currentTime()
    let segmentState = composition.playbackState(at: currentTime)
    eventSink([
      "globalPosition": currentTime.timelineMilliseconds,
      "clipIndex": segmentState.clipIndex,
      "localPosition": segmentState.localPosition.timelineMilliseconds,
      "isPlaying": player.rate != 0,
      "totalDuration": composition.totalDuration.timelineMilliseconds,
    ])
  }

  func dispose() {
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }
    NotificationCenter.default.removeObserver(self)
    player.pause()
    texture.dispose()
    textureRegistry.unregisterTexture(textureId)
    composition.dispose()
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
