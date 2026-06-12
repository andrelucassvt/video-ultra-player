package com.andre.video_ultra_player

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.File
import java.io.FileOutputStream

/**
 * Extracts and caches JPEG thumbnail frames from video files.
 *
 * Thumbnails are stored in `context.cacheDir/vup_thumbs/` and keyed by
 * `{hash(videoPath)}_{timestampMs}_{width}.jpg`. A second call with the
 * same arguments is served from disk cache without re-extraction.
 */
internal class ThumbnailGenerator(private val context: Context) {

    private val thumbDir: File by lazy {
        File(context.cacheDir, "vup_thumbs").also { it.mkdirs() }
    }

    /**
     * Generates thumbnails for [videoPath] at each timestamp in [timestampsMs]
     * (milliseconds) scaled to [width] pixels wide (height is proportional).
     *
     * Must NOT be called on the main thread. Returns an ordered list of
     * absolute paths to the cached JPEG files. Timestamps for which extraction
     * fails are omitted from the result.
     */
    fun generate(videoPath: String, timestampsMs: List<Int>, width: Int): List<String> {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            timestampsMs.mapNotNull { tsMs ->
                generateFrame(retriever, videoPath, tsMs, width)
            }
        } finally {
            retriever.release()
        }
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private fun generateFrame(
        retriever: MediaMetadataRetriever,
        videoPath: String,
        tsMs: Int,
        width: Int,
    ): String? {
        val cacheKey = "${hashPath(videoPath)}_${tsMs}_$width"
        val file = File(thumbDir, "$cacheKey.jpg")
        if (file.exists()) return file.absolutePath

        val timeUs = tsMs.toLong() * 1_000L

        val bitmap: Bitmap = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val nativeW = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1
            val nativeH = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 1
            val scaledHeight = (nativeH.toLong() * width / nativeW).toInt().coerceAtLeast(1)
            retriever.getScaledFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                width,
                scaledHeight,
            )
        } else {
            // API 24–26: retrieve the full frame then scale down.
            val full = retriever.getFrameAtTime(
                timeUs,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            ) ?: return null
            val scaledHeight = (full.height.toLong() * width / full.width).toInt()
                .coerceAtLeast(1)
            Bitmap.createScaledBitmap(full, width, scaledHeight, /* filter = */ true)
        }) ?: return null

        return try {
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            }
            file.absolutePath
        } catch (_: Throwable) {
            null
        }
    }

    /**
     * djb2 hash of [path] encoded as a hex string — used as the cache-key
     * prefix to avoid path-traversal issues and overly long file names.
     */
    private fun hashPath(path: String): String {
        var hash = 5381L
        for (c in path) {
            hash = hash * 33 + c.code
        }
        return hash.toString(16)
    }
}
