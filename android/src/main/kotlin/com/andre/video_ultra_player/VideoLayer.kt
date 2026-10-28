package com.andre.video_ultra_player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.effect.AlphaScale
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * One layer: with three video sequences the multi-input CompositionPlayer
 * preview stalls when the primary sequence switches items (media3 1.10.1).
 */
internal const val MAX_VIDEO_LAYERS = 1

/** Media id of the invisible clips that pad a layer sequence. */
internal const val LAYER_FILLER_MEDIA_ID = "video_ultra_player_layer_filler"

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
    /** Fraction of the frame height; null keeps the source aspect ratio. */
    val heightFraction: Double? = null,
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
        heightFraction?.let { put("heightFraction", it) }
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
                opacity = ((map["opacity"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0),
                heightFraction = (map["heightFraction"] as? Number)?.toDouble()?.coerceIn(0.05, 1.0)
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

/**
 * Pixel size of a layer: [widthFraction] of the frame width; the height is
 * [heightFraction] of the frame height when set (free, stretched), otherwise
 * it follows the source aspect.
 */
internal fun layerPixelSize(
    widthFraction: Double,
    heightFraction: Double? = null,
    sourceWidth: Int,
    sourceHeight: Int,
    renderSize: TimelineRenderSize
): Size {
    val width = evenLayerDimension(widthFraction * renderSize.width)
    if (heightFraction != null) {
        return Size(width, evenLayerDimension(heightFraction * renderSize.height))
    }
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
 * window comes from the invisible filler clips, not from timestamps: the
 * preview player hands the compositor offset presentation times, so a
 * time-window check hid the layer for good. Sequences without a layer (the
 * main one) use the default full-frame settings.
 */
internal class VideoLayerCompositorSettings(
    private val renderSize: TimelineRenderSize,
    private val layersBySequence: Map<Int, PlacedVideoLayer>
) : VideoCompositorSettings {
    // Live placement per layer id, written on the main thread by gestures and
    // read per frame on the GL thread. The composition itself stays as built:
    // only anchor, scale (relative to the baked size) and alpha change.
    private val livePlacements = ConcurrentHashMap<String, VideoLayerDescriptor>()

    fun hasLayer(layerId: String): Boolean =
        layersBySequence.values.any { it.descriptor.id == layerId }

    fun updatePlacement(layer: VideoLayerDescriptor) {
        if (hasLayer(layer.id)) livePlacements[layer.id] = layer
    }

    override fun getOutputSize(inputSizes: List<Size>): Size =
        Size(renderSize.width, renderSize.height)

    /** Placement of the sequence [inputId], or null for the main sequence. */
    fun placementFor(inputId: Int): LayerOverlayPlacement? {
        val baked = layersBySequence[inputId]?.descriptor ?: return null
        val current = livePlacements[baked.id] ?: baked
        val (anchorX, anchorY) = layerAnchorNdc(current.x, current.y)
        // The source was pre-scaled by Presentation to the baked pixel size;
        // live edits scale each axis relative to it (free resize stretches).
        val bakedSize = baked.pixelSize(renderSize)
        val currentSize = current.pixelSize(renderSize)
        return LayerOverlayPlacement(
            anchorX = anchorX,
            anchorY = anchorY,
            scaleX = currentSize.width.toFloat() / bakedSize.width,
            scaleY = currentSize.height.toFloat() / bakedSize.height,
            alpha = current.opacity.toFloat()
        )
    }

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val placement = placementFor(inputId) ?: return StaticOverlaySettings.Builder().build()
        return StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(placement.anchorX, placement.anchorY)
            .setScale(placement.scaleX, placement.scaleY)
            .setAlphaScale(placement.alpha)
            .build()
    }
}

internal data class LayerOverlayPlacement(
    val anchorX: Float,
    val anchorY: Float,
    val scaleX: Float,
    val scaleY: Float,
    val alpha: Float
)

internal fun VideoLayerDescriptor.pixelSize(renderSize: TimelineRenderSize): Size =
    layerPixelSize(
        widthFraction = widthFraction,
        heightFraction = heightFraction,
        sourceWidth = sourceWidth,
        sourceHeight = sourceHeight,
        renderSize = renderSize
    )

/** True when [other] differs from this layer only in x, y, size or opacity. */
internal fun VideoLayerDescriptor.differsOnlyInPlacement(other: VideoLayerDescriptor): Boolean =
    copy(
        x = other.x,
        y = other.y,
        widthFraction = other.widthFraction,
        heightFraction = other.heightFraction,
        opacity = other.opacity
    ) == other

/**
 * Video-only sequence spanning the whole timeline: invisible clips of the same
 * source until the layer starts, the trimmed source pre-scaled to its
 * on-screen size, and invisible clips until the end. Every sequence then has
 * the full duration, so whichever one the player or compositor picks as
 * primary covers the timeline.
 *
 * The padding is video on purpose (media3 1.10.1, multi-input
 * CompositionPlayer): `addGap` stalls seeks into it, and a transparent still
 * froze both videos when the sequence switched from the image to the video.
 * The fillers reuse the layer's decoder and are hidden by `AlphaScale(0)`.
 */
internal fun videoLayerSequence(
    placed: PlacedVideoLayer,
    renderSize: TimelineRenderSize,
    timelineDurationMs: Long
): EditedMediaItemSequence {
    val layer = placed.descriptor
    val visibleMs = placed.windowMs.last - placed.windowMs.first
    val sourceDurationMs = max(layer.sourceDurationMs, layer.trimStartMs + visibleMs)
    val pixelSize = layer.pixelSize(renderSize)
    // Stretch to the exact box: with a free height the video is distorted on
    // purpose; with the source aspect the box already matches it.
    val scaleToLayer = Presentation.createForWidthAndHeight(
        pixelSize.width,
        pixelSize.height,
        Presentation.LAYOUT_STRETCH_TO_FIT
    )
    val item = layerClip(
        layer.path,
        startMs = layer.trimStartMs,
        endMs = layer.trimStartMs + visibleMs,
        sourceDurationMs = sourceDurationMs,
        effects = Effects(emptyList(), listOf(scaleToLayer))
    )

    val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
    val hidden = Effects(emptyList(), listOf(scaleToLayer, AlphaScale(0f)))
    builder.addInvisibleFiller(layer.path, placed.windowMs.first, sourceDurationMs, hidden)
    builder.addItem(item)
    builder.addInvisibleFiller(
        layer.path,
        timelineDurationMs - placed.windowMs.last,
        sourceDurationMs,
        hidden
    )
    return builder.build()
}

/** Covers [durationMs] with invisible clips of the source, each at most its length. */
private fun EditedMediaItemSequence.Builder.addInvisibleFiller(
    path: String,
    durationMs: Long,
    sourceDurationMs: Long,
    hidden: Effects
) {
    var remainingMs = durationMs
    val chunkMs = max(sourceDurationMs, 1L)
    while (remainingMs > 0L) {
        val clipMs = min(remainingMs, chunkMs)
        addItem(
            layerClip(
                path,
                startMs = 0L,
                endMs = clipMs,
                sourceDurationMs = sourceDurationMs,
                effects = hidden,
                mediaId = LAYER_FILLER_MEDIA_ID
            )
        )
        remainingMs -= clipMs
    }
}

private fun layerClip(
    path: String,
    startMs: Long,
    endMs: Long,
    sourceDurationMs: Long,
    effects: Effects,
    mediaId: String? = null
): EditedMediaItem {
    val mediaItem = MediaItem.Builder()
        .setUri(Uri.fromFile(File(path)))
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs(startMs)
                .setEndPositionMs(endMs)
                .build()
        )
    mediaId?.let { mediaItem.setMediaId(it) }
    return EditedMediaItem.Builder(mediaItem.build())
        // Media3 validates the clipping end against the full source duration.
        .setDurationUs(sourceDurationMs * 1_000L)
        .setRemoveAudio(true)
        .setEffects(effects)
        .build()
}
