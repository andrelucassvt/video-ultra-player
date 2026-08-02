import AVFoundation
import Flutter
import QuartzCore

final class TimelineTexture: NSObject, FlutterTexture {
  private let videoOutput: AVPlayerItemVideoOutput
  private weak var textureRegistry: FlutterTextureRegistry?
  private var displayLink: CADisplayLink?
  private let textOverlayRenderer = TimelineTextOverlayRenderer()
  private let frameProcessingQueue = DispatchQueue(
    label: "video_ultra_player.timeline_texture.frames",
    qos: .userInteractive
  )
  private let processingLock = NSLock()
  private var isProcessingFrame = false
  private var overlayGeneration = 0
  private var isDisposed = false

  // Pixel buffer captured on the display-link (main) thread and read on
  // Flutter's rasterizer thread — protected by bufferLock.
  private var pixelBufferCache: CVPixelBuffer?
  private let bufferLock = NSLock()
  // Diagnostic flag — set to true once first frame is captured (remove when fixed).
  private var _didCaptureFirstFrame = false

  var textureId: Int64?

  init(playerItem: AVPlayerItem, textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    videoOutput = AVPlayerItemVideoOutput(
      pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        // Required for Flutter's Metal renderer to create a texture from the buffer.
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
    )
    super.init()
    playerItem.add(videoOutput)
  }

  func start() {
    displayLink?.invalidate()
    displayLink = CADisplayLink(target: self, selector: #selector(onDisplayLink(_:)))
    displayLink?.add(to: .main, forMode: .common)
  }

  /// Detaches the video output from the old player item and attaches it to
  /// [newItem]. Call this before `AVPlayer.replaceCurrentItem` so frames from
  /// the new composition are picked up immediately.
  func replacePlayerItem(_ newItem: AVPlayerItem) {
    newItem.add(videoOutput)
  }

  /// Rebuilds the cached text rasters after a committed overlay mutation.
  /// Existing composited frames are discarded so a paused player cannot keep
  /// showing stale text while the zero-tolerance refresh seek completes.
  func updateTextOverlays(
    _ overlays: [TextOverlayDescriptor],
    renderSize: CGSize,
    totalDuration: CMTime
  ) {
    textOverlayRenderer.update(
      overlays: overlays,
      renderSize: renderSize,
      totalDuration: totalDuration
    )
    processingLock.lock()
    overlayGeneration += 1
    processingLock.unlock()
    bufferLock.lock()
    pixelBufferCache = nil
    bufferLock.unlock()
  }

  /// Asks Flutter to pull a frame immediately. Call after a seek completes to
  /// ensure the first frame appears even when the player is paused.
  func requestFrame() {
    guard let textureId else { return }
    textureRegistry?.textureFrameAvailable(textureId)
  }

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
    processingLock.lock()
    isDisposed = true
    overlayGeneration += 1
    processingLock.unlock()
    bufferLock.lock()
    pixelBufferCache = nil
    bufferLock.unlock()
  }

  // Called from Flutter's rasterizer thread.
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    bufferLock.lock()
    let buffer = pixelBufferCache
    bufferLock.unlock()
    guard let buffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  // Called on main thread at display refresh rate.
  @objc private func onDisplayLink(_ displayLink: CADisplayLink) {
    guard let textureId else { return }

    // Use the display link's own timestamp for accurate item-time mapping,
    // then immediately copy the buffer while that time is still valid.
    let itemTime = videoOutput.itemTime(forHostTime: displayLink.timestamp)

    // Diagnostic: log until we capture a frame (remove once working).
    if !_didCaptureFirstFrame {
      let valid = itemTime.isNumeric
      let hasNew = valid && videoOutput.hasNewPixelBuffer(forItemTime: itemTime)
      NSLog("[TimelineTexture] tick textureId=%lld itemTimeValid=%d hasNew=%d", textureId, valid ? 1 : 0, hasNew ? 1 : 0)
      if !hasNew { return }
      guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
        NSLog("[TimelineTexture] copyPixelBuffer returned nil despite hasNew=true")
        return
      }
      NSLog("[TimelineTexture] FIRST FRAME captured!")
      _didCaptureFirstFrame = true
      enqueueFrame(pixelBuffer, itemTime: itemTime, textureId: textureId)
      return
    }

    guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
          let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: nil
          )
    else { return }

    enqueueFrame(pixelBuffer, itemTime: itemTime, textureId: textureId)
  }

  /// Keeps pixel-buffer drawing away from both Flutter's rasterizer thread and
  /// the main thread. If rendering falls behind, the newest display-link tick
  /// is dropped instead of building a queue that would increase preview lag.
  private func enqueueFrame(
    _ pixelBuffer: CVPixelBuffer,
    itemTime: CMTime,
    textureId: Int64
  ) {
    processingLock.lock()
    guard !isDisposed, !isProcessingFrame else {
      processingLock.unlock()
      return
    }
    isProcessingFrame = true
    let generation = overlayGeneration
    processingLock.unlock()

    frameProcessingQueue.async { [weak self] in
      guard let self else { return }
      self.textOverlayRenderer.render(over: pixelBuffer, at: itemTime)

      self.processingLock.lock()
      let shouldPublish = !self.isDisposed && generation == self.overlayGeneration
      self.isProcessingFrame = false
      self.processingLock.unlock()

      guard shouldPublish else { return }
      self.bufferLock.lock()
      self.pixelBufferCache = pixelBuffer
      self.bufferLock.unlock()

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.processingLock.lock()
        let canNotify = !self.isDisposed && generation == self.overlayGeneration
        self.processingLock.unlock()
        if canNotify {
          self.textureRegistry?.textureFrameAvailable(textureId)
        }
      }
    }
  }
}
