import AVFoundation
import UIKit

/// Process-wide cache of the temporary MP4s generated for image clips.
///
/// Encoding a still into a video is by far the most expensive step of a load,
/// so the result is shared across every `TimelineComposition` in the process
/// and survives a controller `dispose()`. Rebuilding a timeline, switching
/// aspect ratio or re-importing the same still therefore costs a dictionary
/// lookup instead of a full H.264 encode.
final class ImageClipVideoCache {
  static let shared = ImageClipVideoCache()

  /// Stills are static, so a low frame rate produces an identical preview at a
  /// fraction of the encoding cost of the display frame rate.
  private static let framesPerSecond: Int32 = 6
  /// Upper bound for the encoded canvas. Photos routinely exceed the output
  /// resolution by an order of magnitude; encoding them 1:1 only burns time.
  private static let maxDimension: CGFloat = 1_920
  private static let maxEntries = 24

  private struct Key: Hashable {
    let path: String
    let modifiedAt: TimeInterval
    let fileSize: Int64
    let durationMs: Int64
  }

  private let lock = NSLock()
  private var entries: [Key: URL] = [:]
  /// Insertion order of `entries`, oldest first — drives the LRU eviction.
  private var order: [Key] = []

  private lazy var directory: URL = {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("video_ultra_player_image_clips", isDirectory: true)
    // The in-memory index starts empty, so anything already on disk belongs to
    // a previous process run and can never be hit again — drop it instead of
    // letting renders accumulate in tmp across launches.
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  private init() {}

  /// Returns the MP4 rendering `image` (loaded from `path`) for `durationMs`,
  /// encoding it only when it is not already cached on disk.
  func videoURL(
    forImageAt path: String,
    durationMs: Int64
  ) throws -> URL {
    let key = makeKey(path: path, durationMs: durationMs)

    lock.lock()
    if let cached = entries[key], FileManager.default.fileExists(atPath: cached.path) {
      touch(key)
      lock.unlock()
      return cached
    }
    lock.unlock()

    guard let image = UIImage(contentsOfFile: path) else {
      throw TimelineCompositionError.invalidClip
    }

    let url = try encode(
      image: image,
      duration: CMTime(value: max(durationMs, 1), timescale: 1_000)
    )

    lock.lock()
    entries[key] = url
    order.removeAll { $0 == key }
    order.append(key)
    evictIfNeededLocked()
    lock.unlock()
    return url
  }

  /// Drops every cached MP4 from disk. Only used when the plugin detaches —
  /// individual controllers must not invalidate a cache they share.
  func clear() {
    lock.lock()
    let urls = Array(entries.values)
    entries.removeAll()
    order.removeAll()
    lock.unlock()
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }

  // MARK: - Private

  private func makeKey(path: String, durationMs: Int64) -> Key {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return Key(
      path: path,
      modifiedAt: (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
      fileSize: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
      durationMs: max(durationMs, 1)
    )
  }

  /// Moves `key` to the most-recently-used end of `order`. Caller holds `lock`.
  private func touch(_ key: Key) {
    order.removeAll { $0 == key }
    order.append(key)
  }

  /// Caller holds `lock`.
  private func evictIfNeededLocked() {
    while order.count > Self.maxEntries {
      let oldest = order.removeFirst()
      if let url = entries.removeValue(forKey: oldest) {
        try? FileManager.default.removeItem(at: url)
      }
    }
  }

  private func encode(image: UIImage, duration: CMTime) throws -> URL {
    let targetSize = encodeSize(for: image)
    let outputURL = directory.appendingPathComponent(
      "image_\(UUID().uuidString).mp4"
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

    // A still needs a single rasterization — the same buffer is appended at
    // every presentation time instead of being redrawn per frame.
    guard let pixelBuffer = makePixelBuffer(image: image, size: targetSize) else {
      writer.cancelWriting()
      throw TimelineCompositionError.cannotCreateImageVideo
    }

    let fps = Self.framesPerSecond
    let frameCount = max(
      1,
      Int(ceil(CMTimeGetSeconds(duration) * Double(fps)))
    )
    for frame in 0..<frameCount {
      while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.002)
      }
      adaptor.append(
        pixelBuffer,
        withPresentationTime: CMTime(value: Int64(frame), timescale: fps)
      )
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

  private func encodeSize(for image: UIImage) -> CGSize {
    let source = image.size == .zero
      ? CGSize(width: 1_280, height: 720)
      : CGSize(
          width: image.size.width * image.scale,
          height: image.size.height * image.scale
        )
    let longest = max(source.width, source.height)
    let scale = longest > Self.maxDimension ? Self.maxDimension / longest : 1
    return evenSize(CGSize(width: source.width * scale, height: source.height * scale))
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

  private func evenSize(_ size: CGSize) -> CGSize {
    let width = max(2, Int(size.width.rounded()))
    let height = max(2, Int(size.height.rounded()))
    return CGSize(
      width: width.isMultiple(of: 2) ? width : width + 1,
      height: height.isMultiple(of: 2) ? height : height + 1
    )
  }
}
