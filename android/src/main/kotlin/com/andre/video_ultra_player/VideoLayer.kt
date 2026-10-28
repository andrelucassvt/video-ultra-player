package com.andre.video_ultra_player

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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Hardware decoders are limited: every layer decodes alongside the main video. */
internal const val MAX_VIDEO_LAYERS = 3

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
    val sourceHeight: Int = 0
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
 * Positions each layer sequence at its center and hides it outside its window:
 * the gaps around a layer render as opaque blank frames, and the compositor
 * asks for overlay settings per frame, so `alphaScale = 0` keeps them from
 * covering the main video. Sequences without a layer (the main one) use the
 * default full-frame settings.
 */
internal class VideoLayerCompositorSettings(
    private val renderSize: TimelineRenderSize,
    private val layersBySequence: Map<Int, PlacedVideoLayer>
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: List<Size>): Size =
        Size(renderSize.width, renderSize.height)

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val placed = layersBySequence[inputId] ?: return StaticOverlaySettings.Builder().build()
        val timeMs = presentationTimeUs / 1_000L
        val visible = timeMs >= placed.windowMs.first && timeMs < placed.windowMs.last
        val (anchorX, anchorY) = layerAnchorNdc(placed.descriptor.x, placed.descriptor.y)
        return StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(anchorX, anchorY)
            .setAlphaScale(if (visible) placed.descriptor.opacity.toFloat() else 0f)
            .build()
    }
}

/**
 * Video-only sequence spanning the whole timeline: a gap until the layer
 * starts, the trimmed source pre-scaled to its on-screen size, and a gap until
 * the end. Every sequence then has the full duration, so whichever one the
 * player or compositor picks as primary covers the timeline.
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
    val item = EditedMediaItem.Builder(
        MediaItem.Builder()
            .setUri(Uri.fromFile(File(layer.path)))
            .setClippingConfiguration(clipping)
            .build()
    )
        // Media3 validates the clipping end against the full source duration.
        .setDurationUs(max(layer.sourceDurationMs, layer.trimStartMs + visibleMs) * 1_000L)
        .setRemoveAudio(true)
        .setEffects(
            Effects(
                emptyList(),
                listOf(
                    Presentation.createForWidthAndHeight(
                        pixelSize.width,
                        pixelSize.height,
                        Presentation.LAYOUT_SCALE_TO_FIT
                    )
                )
            )
        )
        .build()

    val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
    if (placed.windowMs.first > 0L) builder.addGap(placed.windowMs.first * 1_000L)
    builder.addItem(item)
    val trailingMs = timelineDurationMs - placed.windowMs.last
    if (trailingMs > 0L) builder.addGap(trailingMs * 1_000L)
    return builder.build()
}
