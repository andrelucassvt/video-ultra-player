package com.andre.video_ultra_player

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Hardware decoders are limited: every layer decodes alongside the main video. */
internal const val MAX_VIDEO_LAYERS = 3

/** Media id of the transparent stills that pad a layer sequence. */
internal const val LAYER_FILLER_MEDIA_ID = "video_ultra_player_layer_filler"

private const val LAYER_FILLER_FRAME_RATE = 30

/**
 * Picture-in-picture video layer, mirroring the Dart `TimelineVideoLayer`.
 *
 * [trimEndMs] is an absolute point in the source (null = source end). The
 * `source*` fields are resolved natively and never come from Dart.
 */
internal data class VideoLayerDescriptor(
    val id: String,
    val path: String,
    val startMs: Long,
    val trimStartMs: Long,
    val trimEndMs: Long?,
    val x: Double,
    val y: Double,
    val widthFraction: Double,
    val opacity: Double,
    val sourceDurationMs: Long = 0L,
    val sourceWidth: Int = 0,
    val sourceHeight: Int = 0,
    /** Transparent still that pads the sequence before/after the layer. */
    val fillerImagePath: String = ""
) {
    /** Channel map in the Dart contract format (ms, no native-only fields). */
    fun toMap(): Map<String, Any?> = buildMap {
        put("id", id)
        put("path", path)
        put("startMs", startMs)
        put("trimStartMs", trimStartMs)
        trimEndMs?.let { put("trimEndMs", it) }
        put("x", x)
        put("y", y)
        put("widthFraction", widthFraction)
        put("opacity", opacity)
    }

    /** [toMap] plus the displayed source dimensions, answered to `addVideoLayer`. */
    fun toResponseMap(): Map<String, Any?> =
        toMap() + mapOf("sourceWidth" to sourceWidth, "sourceHeight" to sourceHeight)

    companion object {
        fun from(map: Map<*, *>): VideoLayerDescriptor {
            val id = map["id"] as? String ?: error("Video layer id is required.")
            val path = map["path"] as? String ?: error("Video layer path is required.")
            return VideoLayerDescriptor(
                id = id,
                path = path,
                startMs = ((map["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
                trimStartMs = ((map["trimStartMs"] as? Number)?.toLong() ?: 0L)
                    .coerceAtLeast(0L),
                trimEndMs = (map["trimEndMs"] as? Number)?.toLong(),
                x = ((map["x"] as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0),
                y = ((map["y"] as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0),
                widthFraction = ((map["widthFraction"] as? Number)?.toDouble() ?: 0.5)
                    .coerceIn(0.1, 1.0),
                opacity = ((map["opacity"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
            )
        }
    }
}

/**
 * Timeline window `[first, last)` where the layer is visible, clamped by the
 * timeline end; null when the layer starts after the end or has no length.
 */
internal fun VideoLayerDescriptor.visibleWindowMs(
    sourceDurationMs: Long,
    timelineDurationMs: Long
): LongRange? {
    val sourceEndMs = trimEndMs ?: sourceDurationMs
    val lengthMs = sourceEndMs - trimStartMs
    if (lengthMs <= 0L || startMs >= timelineDurationMs) return null
    return startMs..min(startMs + lengthMs, timelineDurationMs)
}

/**
 * Order of the video sequences in the `Composition`, as indices into the layer
 * list with `-1` for the main sequence. The `DefaultVideoCompositor` draws
 * input 0 on top, so the last layer comes first and the main video last.
 */
internal fun videoSequenceOrder(layerCount: Int): List<Int> =
    (layerCount - 1 downTo 0).toList() + (-1)

/** Pixel size of a layer: [widthFraction] of the frame, height by source aspect. */
internal fun layerPixelSize(
    widthFraction: Double,
    sourceWidth: Int,
    sourceHeight: Int,
    renderSize: TimelineRenderSize
): Size {
    val width = evenLayerDimension(widthFraction * renderSize.width)
    val aspect = if (sourceWidth > 0 && sourceHeight > 0) {
        sourceHeight.toDouble() / sourceWidth
    } else {
        9.0 / 16.0
    }
    return Size(width, evenLayerDimension(width * aspect))
}

/** Layer center in normalized device coordinates: x right, y up, in [-1, 1]. */
internal fun layerAnchorNdc(x: Double, y: Double): Pair<Float, Float> =
    (x * 2.0 - 1.0).toFloat() to (1.0 - y * 2.0).toFloat()

private fun evenLayerDimension(value: Double): Int {
    val rounded = max(value.roundToInt(), 2)
    return if (rounded % 2 == 0) rounded else rounded - 1
}

/** A layer with its visible timeline window already resolved. */
internal data class PlacedVideoLayer(
    val descriptor: VideoLayerDescriptor,
    val windowMs: LongRange
)

/**
 * Positions each layer sequence at its center. Visibility outside the layer
 * window comes from the transparent filler stills, not from timestamps: the
 * preview player hands the compositor offset presentation times, so a
 * time-window check hid the layer for good. Sequences without a layer (the
 * main one) use the default full-frame settings.
 */
internal class VideoLayerCompositorSettings(
    private val renderSize: TimelineRenderSize,
    private val layersBySequence: Map<Int, PlacedVideoLayer>
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: List<Size>): Size =
        Size(renderSize.width, renderSize.height)

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val placed = layersBySequence[inputId] ?: return StaticOverlaySettings.Builder().build()
        val (anchorX, anchorY) = layerAnchorNdc(placed.descriptor.x, placed.descriptor.y)
        return StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(anchorX, anchorY)
            .setAlphaScale(placed.descriptor.opacity.toFloat())
            .build()
    }
}

/**
 * Video-only sequence spanning the whole timeline: a transparent still until
 * the layer starts, the trimmed source pre-scaled to its on-screen size, and a
 * transparent still until the end. Every sequence then has the full duration,
 * so whichever one the player or compositor picks as primary covers the
 * timeline.
 *
 * The padding must be real items, not `addGap`: with a gap in the primary
 * multi-input sequence, a seek into it leaves the main sequence stuck in
 * BUFFERING until `StuckPlayerException` (media3 1.10.1, CompositionPlayer).
 */
internal fun videoLayerSequence(
    placed: PlacedVideoLayer,
    renderSize: TimelineRenderSize,
    timelineDurationMs: Long
): EditedMediaItemSequence {
    val layer = placed.descriptor
    val visibleMs = placed.windowMs.last - placed.windowMs.first
    val clipping = MediaItem.ClippingConfiguration.Builder()
        .setStartPositionMs(layer.trimStartMs)
        .setEndPositionMs(layer.trimStartMs + visibleMs)
        .build()
    val pixelSize = layerPixelSize(
        layer.widthFraction,
        layer.sourceWidth,
        layer.sourceHeight,
        renderSize
    )
    val scaleToLayer = Effects(
        emptyList(),
        listOf(
            Presentation.createForWidthAndHeight(
                pixelSize.width,
                pixelSize.height,
                Presentation.LAYOUT_SCALE_TO_FIT
            )
        )
    )
    val item = EditedMediaItem.Builder(
        MediaItem.Builder()
            .setUri(Uri.fromFile(File(layer.path)))
            .setClippingConfiguration(clipping)
            .build()
    )
        // Media3 validates the clipping end against the full source duration.
        .setDurationUs(max(layer.sourceDurationMs, layer.trimStartMs + visibleMs) * 1_000L)
        .setRemoveAudio(true)
        .setEffects(scaleToLayer)
        .build()

    val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
    val leadingMs = placed.windowMs.first
    if (leadingMs > 0L) builder.addFiller(layer.fillerImagePath, leadingMs, scaleToLayer)
    builder.addItem(item)
    val trailingMs = timelineDurationMs - placed.windowMs.last
    if (trailingMs > 0L) builder.addFiller(layer.fillerImagePath, trailingMs, scaleToLayer)
    return builder.build()
}

private fun EditedMediaItemSequence.Builder.addFiller(
    fillerImagePath: String,
    durationMs: Long,
    effects: Effects
) {
    // Without a filler (should not happen: it is created on resolve) fall
    // back to a gap rather than failing the composition.
    if (fillerImagePath.isEmpty()) {
        addGap(durationMs * 1_000L)
        return
    }
    addItem(
        EditedMediaItem.Builder(
            MediaItem.Builder()
                .setMediaId(LAYER_FILLER_MEDIA_ID)
                .setUri(Uri.fromFile(File(fillerImagePath)))
                .setImageDurationMs(durationMs)
                .build()
        )
            .setDurationUs(durationMs * 1_000L)
            .setFrameRate(LAYER_FILLER_FRAME_RATE)
            .setEffects(effects)
            .build()
    )
}

/**
 * Transparent 2×2 PNG in the cache dir, shared by every layer. Blocking file
 * I/O on first use — call it off the main thread.
 */
internal object LayerFillerImage {
    @Volatile
    private var cachedPath: String? = null

    fun path(context: Context): String {
        cachedPath?.let { if (File(it).exists()) return it }
        synchronized(this) {
            val file = File(context.cacheDir, "video_ultra_player_layer_filler.png")
            if (!file.exists()) {
                val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
                FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            return file.absolutePath.also { cachedPath = it }
        }
    }
}
