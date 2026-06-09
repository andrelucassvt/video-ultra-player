import AVFoundation
import Flutter
import QuartzCore

final class TimelineTexture: NSObject, FlutterTexture {
  private let videoOutput: AVPlayerItemVideoOutput
  private weak var textureRegistry: FlutterTextureRegistry?
  private var displayLink: CADisplayLink?

  var textureId: Int64?

  init(playerItem: AVPlayerItem, textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    videoOutput = AVPlayerItemVideoOutput(
      pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
    guard let pixelBuffer = videoOutput.copyPixelBuffer(
      forItemTime: itemTime,
      itemTimeForDisplay: nil
    ) else {
      return nil
    }
    return Unmanaged.passRetained(pixelBuffer)
  }

  @objc private func onDisplayLink(_ displayLink: CADisplayLink) {
    guard let textureId else {
      return
    }

    let itemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
    if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
      textureRegistry?.textureFrameAvailable(textureId)
    }
  }
}
