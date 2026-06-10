package com.andre.video_ultra_player

import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.Size
import androidx.media3.effect.Crop
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.UUID
import kotlin.math.max
import kotlin.math.min

private const val DEFAULT_WIDTH = 1280
private const val DEFAULT_HEIGHT = 720
private const val DEFAULT_IMAGE_DURATION_MS = 2_000L
private const val STATE_INTERVAL_MS = 33L
private const val EXPORT_PROGRESS_INTERVAL_MS = 100L

internal class TimelineCompositionController(
    private val context: Context,
    private val textureRegistry: TextureRegistry
) {
    private var clips: MutableList<TimelineClip> = mutableListOf()
    private var segments: List<TimelineSegment> = emptyList()
    private var compositionConfig = TimelineCompositionConfig()
    private var renderSize = TimelineRenderSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    private var totalDurationMs: Long = 0L
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    private var player: CompositionPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var disposed = false

    private val stateRunnable = object : Runnable {
        override fun run() {
            emitState()
            if (!disposed) {
                mainHandler.postDelayed(this, STATE_INTERVAL_MS)
            }
        }
    }

    fun load(
        rawClips: List<*>,
        rawConfig: Map<*, *>?
    ): Long {
        compositionConfig = TimelineCompositionConfig.from(rawConfig)
        clips = parseTimelineClips(context, rawClips).toMutableList()
        renderSize = outputSizeFor(compositionConfig, clips.first())
        rebuildSegments()

        val entry = textureRegistry.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(renderSize.width, renderSize.height)
        val renderSurface = Surface(entry.surfaceTexture())

        textureEntry = entry
        surface = renderSurface

        player = CompositionPlayer.Builder(context)
            .build()
            .also { compositionPlayer ->
                compositionPlayer.setVideoSurface(
                    renderSurface,
                    Size(renderSize.width, renderSize.height)
                )
                compositionPlayer.addListener(
                    object : Player.Listener {
                        override fun onPlayerError(error: PlaybackException) {
                            val msg = buildString {
                                append(error.message ?: "CompositionPlayer playback failed.")
                                var cause: Throwable? = error.cause
                                var depth = 0
                                while (cause != null && depth < 5) {
                                    append(" | ")
                                    append(cause.javaClass.simpleName)
                                    cause.message?.let { append(": $it") }
                                    cause = cause.cause
                                    depth++
                                }
                            }
                            eventSink?.error("playback_error", msg, null)
                        }
                    }
                )
                compositionPlayer.setComposition(buildTimelineComposition(clips, renderSize))
                compositionPlayer.prepare()
            }

        mainHandler.post(stateRunnable)
        return entry.id()
    }

    fun setEventSink(eventSink: EventChannel.EventSink?) {
        this.eventSink = eventSink
        emitState()
    }

    fun play() {
        player?.play()
        emitState()
    }

    fun pause() {
        player?.pause()
        emitState()
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs.coerceIn(0L, totalDurationMs))
        emitState()
    }

    fun seekToClip(clipIndex: Int) {
        val startMs = segments.getOrNull(clipIndex)?.startMs ?: return
        player?.seekTo(startMs)
        emitState()
    }

    fun setVolume(volume: Double) {
        player?.volume = volume.coerceIn(0.0, 1.0).toFloat()
        emitState()
    }

    fun setClipAlignment(clipIndex: Int, x: Double, y: Double) {
        if (clipIndex !in clips.indices) {
            return
        }

        clips[clipIndex] = clips[clipIndex].copy(
            alignmentX = x.coerceIn(-1.0, 1.0),
            alignmentY = y.coerceIn(-1.0, 1.0)
        )

        rebuildCompositionPreservingPlayback()
    }

    // MARK: - Editing

    fun trimClip(clipIndex: Int, trimStartMs: Long?, trimEndMs: Long?) {
        if (clipIndex !in clips.indices) return
        var clip = clips[clipIndex]
        if (trimStartMs != null) clip = clip.copy(trimStartMs = trimStartMs)
        if (trimEndMs != null) clip = clip.copy(trimEndMs = trimEndMs)
        clips[clipIndex] = clip
        rebuildCompositionPreservingPlayback()
    }

    fun splitClip(clipIndex: Int, atLocalPositionMs: Long) {
        if (clipIndex !in clips.indices || atLocalPositionMs <= 0) return
        val clip = clips[clipIndex]
        val effectiveTrimStart = clip.trimStartMs ?: 0L
        val absSplitMs = effectiveTrimStart + atLocalPositionMs

        val clipA = clip.copy(
            trimStartMs = if (effectiveTrimStart == 0L) null else effectiveTrimStart,
            trimEndMs = absSplitMs,
            transitionToNextMs = null // hard cut at split boundary
        )
        val clipB = clip.copy(
            trimStartMs = absSplitMs,
            trimEndMs = clip.trimEndMs ?: (
                if (clip.sourceDurationMs > 0) clip.sourceDurationMs else null
            )
        )

        clips.removeAt(clipIndex)
        clips.add(clipIndex, clipB)
        clips.add(clipIndex, clipA)
        rebuildCompositionPreservingPlayback()
    }

    fun insertClip(atIndex: Int, rawClip: Map<*, *>) {
        val resolved = resolveClip(context, TimelineClip.from(rawClip))
        val safeIndex = atIndex.coerceIn(0, clips.size)
        clips.add(safeIndex, resolved)
        rebuildCompositionPreservingPlayback()
    }

    fun removeClip(clipIndex: Int) {
        if (clipIndex !in clips.indices) return
        clips.removeAt(clipIndex)
        rebuildCompositionPreservingPlayback()
    }

    fun moveClip(fromIndex: Int, toIndex: Int) {
        if (fromIndex !in clips.indices || toIndex !in clips.indices || fromIndex == toIndex) return
        val clip = clips.removeAt(fromIndex)
        clips.add(toIndex.coerceIn(0, clips.size), clip)
        rebuildCompositionPreservingPlayback()
    }

    fun replaceClip(clipIndex: Int, rawClip: Map<*, *>) {
        if (clipIndex !in clips.indices) return
        clips[clipIndex] = resolveClip(context, TimelineClip.from(rawClip))
        rebuildCompositionPreservingPlayback()
    }

    fun startExportCurrentTimeline(
        outputPath: String?,
        callback: TimelineExportCallback
    ): TimelineCompositionExporter {
        val currentClips = clips.toList()
        val currentRenderSize = renderSize
        return TimelineCompositionExporter(context).also { exporter ->
            exporter.exportFromClips(currentClips, currentRenderSize, outputPath, callback)
        }
    }

    fun dispose() {
        disposed = true
        mainHandler.removeCallbacks(stateRunnable)
        eventSink = null
        player?.release()
        player = null
        surface?.release()
        surface = null
        textureEntry?.release()
        textureEntry = null
    }

    private fun rebuildSegments() {
        var startMs = 0L
        segments = clips.map { clip ->
            TimelineSegment(startMs = startMs, durationMs = clip.resolvedDurationMs).also {
                startMs += clip.resolvedDurationMs
            }
        }
        totalDurationMs = startMs
    }

    private fun rebuildCompositionPreservingPlayback() {
        rebuildSegments()
        val currentPlayer = player ?: return
        val positionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val wasPlaying = currentPlayer.isPlaying
        currentPlayer.setComposition(
            buildTimelineComposition(clips, renderSize),
            positionMs.coerceIn(0L, totalDurationMs)
        )
        currentPlayer.prepare()
        if (wasPlaying) {
            currentPlayer.play()
        }
        emitState()
    }

    private fun emitState() {
        val currentPlayer = player
        val positionMs = currentPlayer?.currentPosition?.coerceAtLeast(0L) ?: 0L
        val segmentIndex = segmentIndexFor(positionMs)
        val segment = segments.getOrNull(segmentIndex)
        eventSink?.success(
            mapOf(
                "globalPosition" to positionMs.coerceAtMost(totalDurationMs),
                "clipIndex" to segmentIndex,
                "localPosition" to (
                    segment?.let { positionMs - it.startMs } ?: 0L
                    ).coerceAtLeast(0L),
                "isPlaying" to (currentPlayer?.isPlaying == true),
                "totalDuration" to totalDurationMs,
                "clipDurationsMs" to segments.map { it.durationMs }
            )
        )
    }

    private fun segmentIndexFor(positionMs: Long): Int {
        if (segments.isEmpty()) {
            return 0
        }

        for (index in segments.indices.reversed()) {
            val segment = segments[index]
            if (positionMs >= segment.startMs && positionMs < segment.startMs + segment.durationMs) {
                return index
            }
        }
        return segments.lastIndex
    }
}

internal interface TimelineExportCallback {
    fun onProgress(progress: Double, state: String)
    fun onCompleted(outputPath: String)
    fun onError(error: Throwable)
}

internal class TimelineCompositionExporter(
    private val context: Context
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var completed = false
    private val progressHolder = ProgressHolder()
    private var progressCallback: TimelineExportCallback? = null
    private val progressRunnable = object : Runnable {
        override fun run() {
            val exportTransformer = transformer
            val callback = progressCallback
            if (exportTransformer != null && callback != null && !completed) {
                val state = exportTransformer.getProgress(progressHolder)
                val progress = if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    progressHolder.progress.coerceIn(0, 100) / 100.0
                } else {
                    0.0
                }
                callback.onProgress(progress, "exporting")
                mainHandler.postDelayed(this, EXPORT_PROGRESS_INTERVAL_MS)
            }
        }
    }

    fun export(
        rawClips: List<*>,
        rawConfig: Map<*, *>?,
        outputPath: String?,
        callback: TimelineExportCallback
    ) {
        val config = TimelineCompositionConfig.from(rawConfig)
        val parsedClips = parseTimelineClips(context, rawClips)
        val outputSize = outputSizeFor(config, parsedClips.first())
        exportFromClips(parsedClips, outputSize, outputPath, callback)
    }

    fun exportFromClips(
        clips: List<TimelineClip>,
        renderSize: TimelineRenderSize,
        outputPath: String?,
        callback: TimelineExportCallback
    ) {
        progressCallback = callback
        callback.onProgress(0.0, "exporting")
        val outputFile = exportOutputFile(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val composition = buildTimelineComposition(clips, renderSize)
        val exportTransformer = Transformer.Builder(context)
            .addListener(
                object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult
                    ) {
                        complete {
                            callback.onProgress(1.0, "completed")
                            callback.onCompleted(outputFile.absolutePath)
                        }
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        outputFile.delete()
                        complete {
                            callback.onProgress(
                                progressHolder.progress.coerceIn(0, 100) / 100.0,
                                "failed"
                            )
                            callback.onError(exportException)
                        }
                    }
                }
            )
            .build()

        transformer = exportTransformer
        exportTransformer.start(composition, outputFile.absolutePath)
        mainHandler.post(progressRunnable)
    }

    fun cancel() {
        completed = true
        mainHandler.removeCallbacks(progressRunnable)
        transformer?.cancel()
        transformer = null
        progressCallback = null
    }

    private fun complete(block: () -> Unit) {
        if (completed) {
            return
        }
        completed = true
        mainHandler.removeCallbacks(progressRunnable)
        mainHandler.post {
            transformer = null
            progressCallback = null
            block()
        }
    }

    private fun exportOutputFile(outputPath: String?): File {
        if (!outputPath.isNullOrBlank()) {
            return File(outputPath)
        }

        return File(
            context.cacheDir,
            "video_ultra_player_export_${UUID.randomUUID()}.mp4"
        )
    }
}

private fun buildTimelineComposition(
    clips: List<TimelineClip>,
    renderSize: TimelineRenderSize
): Composition {
    val items = clips.map { clip -> editedMediaItemFor(clip, renderSize) }
    val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(items)
    return Composition.Builder(listOf(sequence)).build()
}

private fun editedMediaItemFor(
    clip: TimelineClip,
    renderSize: TimelineRenderSize
): EditedMediaItem {
    val mediaItemBuilder = MediaItem.Builder()
        .setUri(Uri.fromFile(File(clip.path)))

    if (clip.type == TimelineMediaType.IMAGE) {
        mediaItemBuilder.setImageDurationMs(clip.resolvedDurationMs)
    } else if (clip.trimStartMs != null || clip.trimEndMs != null) {
        val clippingBuilder = MediaItem.ClippingConfiguration.Builder()
        clip.trimStartMs?.let { clippingBuilder.setStartPositionMs(it) }
        clip.trimEndMs?.let { clippingBuilder.setEndPositionMs(it) }
        mediaItemBuilder.setClippingConfiguration(clippingBuilder.build())
    }

    val builder = EditedMediaItem.Builder(mediaItemBuilder.build())
        .setDurationUs(clip.resolvedDurationMs * 1_000L)
        .setEffects(effectsFor(clip, renderSize))

    if (clip.type == TimelineMediaType.IMAGE) {
        builder.setFrameRate(30)
    }

    return builder.build()
}

private fun effectsFor(
    clip: TimelineClip,
    renderSize: TimelineRenderSize
): Effects {
    val effects = mutableListOf<Effect>()
    val scale = max(clip.scale, 1.0)
    if (scale > 1.0001) {
        val visibleSpan = (2.0 / scale).coerceIn(0.05, 2.0).toFloat()
        val extraSpan = 2.0f - visibleSpan
        val horizontalBias = ((clip.alignmentX + 1.0) / 2.0).toFloat()
        val verticalBias = ((clip.alignmentY + 1.0) / 2.0).toFloat()
        val left = -1.0f + extraSpan * horizontalBias
        val right = left + visibleSpan
        val top = 1.0f - extraSpan * verticalBias
        val bottom = top - visibleSpan

        effects.add(
            Crop(
                min(left, right - 0.01f),
                max(right, left + 0.01f),
                min(bottom, top - 0.01f),
                max(top, bottom + 0.01f)
            )
        )
    }

    effects.add(
        Presentation.createForWidthAndHeight(
            renderSize.width,
            renderSize.height,
            Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
        )
    )
    return Effects(emptyList(), effects)
}

private fun parseTimelineClips(
    context: Context,
    rawClips: List<*>
): List<TimelineClip> {
    require(rawClips.isNotEmpty()) { "Timeline must contain at least one clip." }

    return rawClips.map { raw ->
        TimelineClip.from(raw as? Map<*, *> ?: error("Invalid timeline clip."))
    }.map { clip ->
        resolveClip(context, clip)
    }
}

private fun resolveClip(context: Context, clip: TimelineClip): TimelineClip {
    val sourceSize = resolveSourceSize(context, clip)
    val sourceDurationMs = if (clip.type == TimelineMediaType.VIDEO) {
        resolveSourceDurationMs(context, clip)
    } else 0L
    return clip.copy(
        sourceDurationMs = sourceDurationMs,
        sourceWidth = sourceSize.width,
        sourceHeight = sourceSize.height
    )
}

private fun resolveSourceDurationMs(context: Context, clip: TimelineClip): Long {
    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(context, Uri.fromFile(File(clip.path)))
        retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull()
            ?.let { max(it, 1L) }
            ?: DEFAULT_IMAGE_DURATION_MS
    } finally {
        retriever.release()
    }
}

private fun resolveSourceSize(
    context: Context,
    clip: TimelineClip
): TimelineRenderSize {
    if (clip.type == TimelineMediaType.IMAGE) {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(clip.path, options)
        return TimelineRenderSize(
            width = evenDimension(options.outWidth.takeIf { it > 0 } ?: DEFAULT_WIDTH),
            height = evenDimension(options.outHeight.takeIf { it > 0 } ?: DEFAULT_HEIGHT)
        )
    }

    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(context, Uri.fromFile(File(clip.path)))
        val width = retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
            ?.toIntOrNull()
            ?: DEFAULT_WIDTH
        val height = retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
            ?.toIntOrNull()
            ?: DEFAULT_HEIGHT
        val rotation = retriever
            .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
            ?.toIntOrNull()
            ?: 0
        if (rotation == 90 || rotation == 270) {
            TimelineRenderSize(evenDimension(height), evenDimension(width))
        } else {
            TimelineRenderSize(evenDimension(width), evenDimension(height))
        }
    } finally {
        retriever.release()
    }
}

private fun outputSizeFor(
    config: TimelineCompositionConfig,
    firstClip: TimelineClip
): TimelineRenderSize {
    val base = evenDimension(config.baseWidth)
    return when (config.aspectRatio) {
        OutputAspectRatio.RATIO_16X9 -> TimelineRenderSize(
            width = base,
            height = evenDimension(base * 9 / 16)
        )
        OutputAspectRatio.RATIO_9X16 -> TimelineRenderSize(
            width = evenDimension(base * 9 / 16),
            height = base
        )
        OutputAspectRatio.RATIO_1X1 -> TimelineRenderSize(width = base, height = base)
        OutputAspectRatio.ORIGINAL -> TimelineRenderSize(
            width = evenDimension(firstClip.sourceWidth),
            height = evenDimension(firstClip.sourceHeight)
        )
    }
}

private fun evenDimension(value: Int): Int {
    val safeValue = max(value, 2)
    return if (safeValue % 2 == 0) safeValue else safeValue + 1
}

private data class TimelineSegment(
    val startMs: Long,
    val durationMs: Long
)

private data class TimelineCompositionConfig(
    val aspectRatio: OutputAspectRatio = OutputAspectRatio.ORIGINAL,
    val baseWidth: Int = 1080
) {
    companion object {
        fun from(map: Map<*, *>?): TimelineCompositionConfig {
            val aspectRatio = when (map?.get("aspectRatio") as? String) {
                "ratio16x9" -> OutputAspectRatio.RATIO_16X9
                "ratio9x16" -> OutputAspectRatio.RATIO_9X16
                "ratio1x1" -> OutputAspectRatio.RATIO_1X1
                else -> OutputAspectRatio.ORIGINAL
            }
            return TimelineCompositionConfig(
                aspectRatio = aspectRatio,
                baseWidth = ((map?.get("baseWidth") as? Number)?.toInt() ?: 1080)
                    .coerceAtLeast(1)
            )
        }
    }
}

internal data class TimelineRenderSize(
    val width: Int,
    val height: Int
)

internal data class TimelineClip(
    val path: String,
    val type: TimelineMediaType,
    val durationMs: Long?,
    val alignmentX: Double,
    val alignmentY: Double,
    val scale: Double,
    val trimStartMs: Long? = null,
    val trimEndMs: Long? = null,
    val transitionToNextMs: Long? = null,
    val sourceDurationMs: Long = 0L,
    val sourceWidth: Int = DEFAULT_WIDTH,
    val sourceHeight: Int = DEFAULT_HEIGHT
) {
    val resolvedDurationMs: Long
        get() {
            if (type == TimelineMediaType.IMAGE) {
                return max(durationMs ?: DEFAULT_IMAGE_DURATION_MS, 1L)
            }
            val effectiveTrimStart = trimStartMs ?: 0L
            if (trimEndMs != null) {
                return max(trimEndMs - effectiveTrimStart, 1L)
            }
            val effectiveSourceEnd = if (sourceDurationMs > 0) sourceDurationMs
            else (durationMs ?: DEFAULT_IMAGE_DURATION_MS)
            return max(effectiveSourceEnd - effectiveTrimStart, 1L)
        }

    companion object {
        fun from(map: Map<*, *>): TimelineClip {
            val path = map["path"] as? String ?: error("Clip path is required.")
            val type = when (map["type"] as? String) {
                "image" -> TimelineMediaType.IMAGE
                else -> TimelineMediaType.VIDEO
            }
            val durationMs = (map["durationMs"] as? Number)?.toLong()
            val alignment = map["alignment"] as? Map<*, *>
            val alignmentX = (alignment?.get("x") as? Number)?.toDouble() ?: 0.0
            val alignmentY = (alignment?.get("y") as? Number)?.toDouble() ?: 0.0
            val scale = (map["scale"] as? Number)?.toDouble() ?: 1.0
            val trimStartMs = (map["trimStartMs"] as? Number)?.toLong()
            val trimEndMs = (map["trimEndMs"] as? Number)?.toLong()
            val transitionToNextMs = (map["transitionToNext"] as? Map<*, *>)
                ?.let { (it["durationMs"] as? Number)?.toLong() }

            return TimelineClip(
                path = path,
                type = type,
                durationMs = durationMs,
                alignmentX = alignmentX,
                alignmentY = alignmentY,
                scale = max(scale, 0.01),
                trimStartMs = trimStartMs,
                trimEndMs = trimEndMs,
                transitionToNextMs = transitionToNextMs
            )
        }
    }
}

internal enum class TimelineMediaType {
    VIDEO,
    IMAGE
}

private enum class OutputAspectRatio {
    RATIO_16X9,
    RATIO_9X16,
    RATIO_1X1,
    ORIGINAL
}
