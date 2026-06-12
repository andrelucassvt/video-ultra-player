import AVFoundation
import UIKit

/// Extracts and caches JPEG thumbnail frames from video files.
///
/// Thumbnails are stored in `NSTemporaryDirectory()/vup_thumbs/` and keyed
/// by `{hash(videoPath)}_{timestampMs}_{width}.jpg`. A second call with the
/// same arguments is served from the cache without re-extraction.
final class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    private let thumbDir: URL

    private init() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vup_thumbs")
        try? FileManager.default.createDirectory(
            at: tmp,
            withIntermediateDirectories: true
        )
        thumbDir = tmp
    }

    /// Generates thumbnails for [videoPath] at each timestamp in [timestampsMs]
    /// (milliseconds) scaled to [width] pixels wide.
    ///
    /// Executes synchronously on a background thread and calls [completion]
    /// on that same background thread with the ordered list of cached file
    /// paths. Callers must dispatch back to the main thread when needed.
    ///
    /// Zero-tolerance extraction (`requestedTimeToleranceBefore/After = .zero`)
    /// gives frame-exact results at the cost of higher latency. Use a small
    /// non-zero tolerance (e.g. `CMTimeMake(1, 10)`) if speed is preferred
    /// over precision.
    func generate(
        videoPath: String,
        timestampsMs: [Int],
        width: Int,
        completion: @escaping ([String]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                completion([])
                return
            }

            let url = URL(fileURLWithPath: videoPath)
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Zero tolerance: frame-exact extraction (slower but precise).
            // Tradeoff: replace with CMTimeMake(1, 10) for better performance
            // when exact frame accuracy is not required.
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            var paths: [String] = []
            for tsMs in timestampsMs {
                let cacheKey = "\(self.hashPath(videoPath))_\(tsMs)_\(width)"
                let fileURL = self.thumbDir
                    .appendingPathComponent("\(cacheKey).jpg")

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    paths.append(fileURL.path)
                    continue
                }

                let time = CMTime(
                    value: CMTimeValue(tsMs),
                    timescale: 1000
                )
                guard let cgImage = try? generator.copyCGImage(
                    at: time,
                    actualTime: nil
                ) else {
                    continue
                }

                let uiImage = UIImage(cgImage: cgImage)
                let scaled = self.scale(uiImage, toWidth: width)
                if let data = scaled.jpegData(compressionQuality: 0.8) {
                    try? data.write(to: fileURL)
                    paths.append(fileURL.path)
                }
            }

            completion(paths)
        }
    }

    // MARK: - Private helpers

    /// djb2 hash of the path encoded as a hex string — used as the cache-key
    /// prefix to avoid path-traversal issues and long file names.
    private func hashPath(_ path: String) -> String {
        var hash: UInt64 = 5381
        for byte in path.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private func scale(_ image: UIImage, toWidth width: Int) -> UIImage {
        let targetWidth = CGFloat(width)
        let scale = targetWidth / image.size.width
        let newSize = CGSize(
            width: targetWidth,
            height: (image.size.height * scale).rounded()
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
