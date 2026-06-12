import AVFoundation
import Flutter
import QuartzCore

final class TimelineTexture: NSObject, FlutterTexture {
  private let videoOutput: AVPlayerItemVideoOutput
  private weak var textureRegistry: FlutterTextureRegistry?
  private var displayLink: CADisplayLink?

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

  /// Asks Flutter to pull a frame immediately. Call after a seek completes to
  /// ensure the first frame appears even when the player is paused.
  func requestFrame() {
    guard let textureId else { return }
    textureRegistry?.textureFrameAvailable(textureId)
  }

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
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
      bufferLock.lock()
      pixelBufferCache = pixelBuffer
      bufferLock.unlock()
      textureRegistry?.textureFrameAvailable(textureId)
      return
    }

    guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
          let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: itemTime,
            itemTimeForDisplay: nil
          )
    else { return }

    bufferLock.lock()
    pixelBufferCache = pixelBuffer
    bufferLock.unlock()

    textureRegistry?.textureFrameAvailable(textureId)
  }
}
