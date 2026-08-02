package com.andre.video_ultra_player

import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableString
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.AlignmentSpan
import android.text.style.BackgroundColorSpan
import android.text.style.ForegroundColorSpan
import android.text.style.MetricAffectingSpan
import androidx.media3.common.OverlaySettings
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import kotlin.math.max
import kotlin.math.min

internal enum class TextOverlayTextAlign {
    LEFT,
    CENTER,
    RIGHT
}

/**
 * Describes a text overlay burned into the composed video, identical in the
 * preview and the exported MP4.
 *
 * [x] and [y] are the center of the text in normalized frame coordinates
 * (`(0, 0)` is the top-left corner, `(1, 1)` is the bottom-right).
 * [fontSize] is a fraction of the video height.
 */
internal data class TextOverlayDescriptor(
    val id: String,
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val x: Double,
    val y: Double,
    val rotationDegrees: Double,
    val fontSize: Double,
    val color: Int,
    val fontFamily: String?,
    val fontPath: String?,
    val backgroundColor: Int,
    val opacity: Double,
    val textAlign: TextOverlayTextAlign
) {
    companion object {
        fun from(map: Map<*, *>): TextOverlayDescriptor {
            val id = map["id"] as? String ?: error("Text overlay id is required.")
            val text = map["text"] as? String ?: error("Text overlay text is required.")
            val textAlign = when (map["textAlign"] as? String) {
                "left" -> TextOverlayTextAlign.LEFT
                "right" -> TextOverlayTextAlign.RIGHT
                else -> TextOverlayTextAlign.CENTER
            }
            return TextOverlayDescriptor(
                id = id,
                text = text,
                startMs = ((map["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
                endMs = ((map["endMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
                x = ((map["x"] as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0),
                y = ((map["y"] as? Number)?.toDouble() ?: 0.5).coerceIn(0.0, 1.0),
                rotationDegrees = (map["rotationDegrees"] as? Number)?.toDouble() ?: 0.0,
                fontSize = ((map["fontSize"] as? Number)?.toDouble() ?: 0.05)
                    .coerceIn(0.0001, 1.0),
                color = (map["color"] as? Number)?.toInt() ?: 0xFFFFFFFF.toInt(),
                fontFamily = map["fontFamily"] as? String,
                fontPath = map["fontPath"] as? String,
                backgroundColor = (map["backgroundColor"] as? Number)?.toInt() ?: 0,
                opacity = ((map["opacity"] as? Number)?.toDouble() ?: 1.0).coerceIn(0.0, 1.0),
                textAlign = textAlign
            )
        }
    }
}

/**
 * Filters and re-anchors timeline-level overlays to a single clip window.
 *
 * Media3 effect timestamps are relative to the [androidx.media3.common.MediaItem],
 * not the timeline — so overlays are intersected with `[clipStartMs,
 * clipStartMs + clipDurationMs)` and their window is shifted by `clipStartMs`.
 */
internal fun textOverlaysForClip(
    overlays: List<TextOverlayDescriptor>,
    clipStartMs: Long,
    clipDurationMs: Long
): List<TextOverlayDescriptor> {
    val clipEndMs = clipStartMs + clipDurationMs
    return overlays.mapNotNull { overlay ->
        val visibleStartMs = max(overlay.startMs, clipStartMs)
        val visibleEndMs = min(overlay.endMs, clipEndMs)
        if (visibleStartMs >= visibleEndMs) {
            null
        } else {
            overlay.copy(
                startMs = (visibleStartMs - clipStartMs).coerceAtLeast(0L),
                endMs = (visibleEndMs - clipStartMs).coerceAtLeast(0L)
            )
        }
    }
}

/**
 * Media3 [TextOverlay] that renders one [TextOverlayDescriptor] on a single
 * clip. Returns an empty string outside the overlay's window (no-op render).
 */
internal class TimelineTextOverlay(
    private val descriptor: TextOverlayDescriptor,
    private val renderHeight: Int
) : TextOverlay() {

    override fun getText(presentationTimeUs: Long): SpannableString {
        val timeMs = presentationTimeUs / 1_000
        if (timeMs < descriptor.startMs || timeMs >= descriptor.endMs) {
            return SpannableString("")
        }

        val span = SpannableString(descriptor.text)
        val textSizePx = (descriptor.fontSize * renderHeight).toInt().coerceAtLeast(1)
        val align = when (descriptor.textAlign) {
            TextOverlayTextAlign.LEFT -> Layout.Alignment.ALIGN_NORMAL
            TextOverlayTextAlign.RIGHT -> Layout.Alignment.ALIGN_OPPOSITE
            TextOverlayTextAlign.CENTER -> Layout.Alignment.ALIGN_CENTER
        }

        span.setSpan(
            ForegroundColorSpan(descriptor.color),
            0,
            span.length,
            SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        if (descriptor.backgroundColor ushr 24 > 0) {
            span.setSpan(
                BackgroundColorSpan(descriptor.backgroundColor),
                0,
                span.length,
                SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        span.setSpan(
            AbsoluteSizeSpan(textSizePx, false),
            0,
            span.length,
            SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        span.setSpan(
            AlignmentSpan.Standard(align),
            0,
            span.length,
            SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        span.setSpan(
            OverlayTypefaceSpan(resolveTypeface()),
            0,
            span.length,
            SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        return span
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        // Convert the center (x, y) in 0..1 top-left space to NDC (-1..1, y flipped).
        val ndcX = (descriptor.x * 2 - 1).toFloat()
        val ndcY = (1 - descriptor.y * 2).toFloat()
        return StaticOverlaySettings.Builder()
            .setOverlayFrameAnchor(ndcX, ndcY)
            .setBackgroundFrameAnchor(ndcX, ndcY)
            .setRotationDegrees(descriptor.rotationDegrees.toFloat())
            .setAlphaScale(descriptor.opacity.toFloat())
            .build()
    }

    private fun resolveTypeface(): Typeface {
        return typefaceFor(descriptor.fontPath, descriptor.fontFamily)
    }

    private class OverlayTypefaceSpan(
        private val typeface: Typeface
    ) : MetricAffectingSpan() {
        override fun updateDrawState(textPaint: TextPaint) {
            textPaint.typeface = typeface
        }

        override fun updateMeasureState(textPaint: TextPaint) {
            textPaint.typeface = typeface
        }
    }

    companion object {
        // Typeface.createFromFile does I/O — cache by path so it never happens
        // per frame.
        private val typefaceCache = HashMap<String, Typeface>()

        private fun typefaceFor(fontPath: String?, fontFamily: String?): Typeface {
            if (fontPath != null) {
                typefaceCache[fontPath]?.let { return it }
                val fromFile = try {
                    Typeface.createFromFile(fontPath)
                } catch (e: Throwable) {
                    null
                }
                if (fromFile != null) {
                    typefaceCache[fontPath] = fromFile
                    return fromFile
                }
            }
            if (fontFamily != null) {
                val fromFamily = try {
                    Typeface.create(fontFamily, Typeface.NORMAL)
                } catch (e: Throwable) {
                    null
                }
                if (fromFamily != null && fromFamily != Typeface.DEFAULT) {
                    return fromFamily
                }
            }
            return Typeface.DEFAULT
        }
    }
}
