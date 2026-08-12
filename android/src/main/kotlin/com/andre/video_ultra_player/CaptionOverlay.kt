package com.andre.video_ultra_player

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableString
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import androidx.media3.effect.BitmapOverlay

internal data class CaptionWordDescriptor(
    val text: String,
    val startMs: Long,
    val endMs: Long
) {
    companion object {
        fun from(map: Map<*, *>): CaptionWordDescriptor {
            return CaptionWordDescriptor(
                text = map["text"] as? String ?: error("Caption word text is required."),
                startMs = ((map["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L),
                endMs = ((map["endMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
            )
        }
    }
}

/**
 * One caption cue visible on the timeline during `[startMs, endMs)`.
 *
 * [words] carries the per-word windows used by the karaoke style; it is never
 * null (the Dart side serialises an empty list when no words are present).
 */
internal data class CaptionCueDescriptor(
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val words: List<CaptionWordDescriptor>
) {
    companion object {
        fun from(map: Map<*, *>): CaptionCueDescriptor {
            val text = map["text"] as? String ?: error("Caption cue text is required.")
            val startMs = ((map["startMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
            val endMs = ((map["endMs"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
            @Suppress("UNCHECKED_CAST")
            val rawWords = map["words"] as? List<*> ?: emptyList<Any?>()
            val words = rawWords
                .mapNotNull { it as? Map<*, *> }
                .map { CaptionWordDescriptor.from(it) }
            return CaptionCueDescriptor(text = text, startMs = startMs, endMs = endMs, words = words)
        }
    }
}

/**
 * Visual style applied to every caption cue. Colors are ARGB ints,
 * [fontSize] and [strokeWidth] are fractions of the video height,
 * [positionY] is the center of the caption block in normalized frame
 * coordinates (`0.0` top edge, `1.0` bottom edge).
 */
internal data class CaptionStyleDescriptor(
    val color: Int,
    val fontSize: Double,
    val positionY: Double,
    val uppercase: Boolean,
    val karaoke: Boolean,
    val strokeWidth: Double,
    val backgroundOpacity: Double,
    val highlightColor: Int
) {
    companion object {
        fun from(map: Map<*, *>): CaptionStyleDescriptor {
            return CaptionStyleDescriptor(
                color = (map["color"] as? Number)?.toInt() ?: 0xFFFFFFFF.toInt(),
                fontSize = ((map["fontSize"] as? Number)?.toDouble() ?: 0.055)
                    .coerceIn(0.0001, 1.0),
                positionY = ((map["positionY"] as? Number)?.toDouble() ?: 0.85)
                    .coerceIn(0.0, 1.0),
                uppercase = map["uppercase"] as? Boolean ?: false,
                karaoke = map["karaoke"] as? Boolean ?: false,
                strokeWidth = ((map["strokeWidth"] as? Number)?.toDouble() ?: 0.0)
                    .coerceAtLeast(0.0),
                backgroundOpacity = ((map["backgroundOpacity"] as? Number)?.toDouble() ?: 0.0)
                    .coerceIn(0.0, 1.0),
                highlightColor = (map["highlightColor"] as? Number)?.toInt() ?: 0xFFFFD700.toInt()
            )
        }
    }
}

/**
 * Returns the cue whose timeline window `[startMs, endMs)` contains the
 * presentation time (converted from the clip-local [presentationTimeUs] to
 * timeline time via [clipStartMs]).
 *
 * Windows are half-open; when two cues overlap at the exact boundary, the
 * first cue in the list wins.
 */
internal fun activeCaptionCue(
    cues: List<CaptionCueDescriptor>,
    clipStartMs: Long,
    presentationTimeUs: Long
): CaptionCueDescriptor? {
    val timelineMs = clipStartMs + presentationTimeUs / 1_000
    return cues.firstOrNull { timelineMs >= it.startMs && timelineMs < it.endMs }
}

/**
 * Media3 [BitmapOverlay] that renders the active caption cue on a single
 * full-frame bitmap.
 *
 * The bitmap is cached and only re-rendered when the active cue — or, in
 * karaoke mode, the highlighted word — changes, instead of every frame.
 */
internal class CaptionOverlay(
    private val cues: List<CaptionCueDescriptor>,
    private val captionStyle: CaptionStyleDescriptor,
    private val renderWidth: Int,
    private val renderHeight: Int,
    private val clipStartMs: Long
) : BitmapOverlay() {
    private var cachedCue: CaptionCueDescriptor? = null
    private var cachedWordIndex = -1
    private var cachedBitmap: Bitmap? = null

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val cue = activeCaptionCue(cues, clipStartMs, presentationTimeUs)
        val wordIndex = if (captionStyle.karaoke && cue != null) {
            activeWordIndex(cue, clipStartMs, presentationTimeUs)
        } else {
            -1
        }
        if (cue != cachedCue || wordIndex != cachedWordIndex) {
            cachedCue = cue
            cachedWordIndex = wordIndex
            cachedBitmap = null
        }
        var bitmap = cachedBitmap
        if (bitmap == null) {
            bitmap = renderCue(cue, wordIndex)
            cachedBitmap = bitmap
        }
        return bitmap
    }

    private fun renderCue(
        cue: CaptionCueDescriptor?,
        activeWordIndex: Int
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(renderWidth, renderHeight, Bitmap.Config.ARGB_8888)
        val rawText = cue?.text ?: ""
        val text = if (captionStyle.uppercase) rawText.uppercase() else rawText
        if (text.isEmpty()) {
            return bitmap
        }
        val canvas = Canvas(bitmap)
        val textSizePx = (captionStyle.fontSize * renderHeight).toFloat().coerceAtLeast(1f)
        val maxWidthPx = (renderWidth * 0.92f).toInt().coerceAtLeast(1)
        val anchorY = (captionStyle.positionY * renderHeight).toFloat()

        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.textSize = textSizePx
            this.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            this.textAlign = Paint.Align.CENTER
            this.color = captionStyle.color
        }

        val fillText = karaokeSpannable(text, cue, activeWordIndex)
        val fillLayout = StaticLayout.Builder
            .obtain(fillText, 0, fillText.length, paint, maxWidthPx)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setIncludePad(true)
            .build()

        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            alpha = (captionStyle.backgroundOpacity * 255).toInt().coerceIn(0, 255)
        }
        if (background.alpha > 0) {
            val padding = textSizePx * 0.3f
            val textWidth = fillLayout.getLineWidth(0)
            val rect = RectF(
                (renderWidth - textWidth) / 2f - padding,
                anchorY - fillLayout.height / 2f - padding,
                (renderWidth + textWidth) / 2f + padding,
                anchorY + fillLayout.height / 2f + padding
            )
            canvas.drawRoundRect(rect, padding * 0.5f, padding * 0.5f, background)
        }

        val strokePx = (captionStyle.strokeWidth * renderHeight).toFloat()
        if (strokePx > 0f) {
            // Stroke pass without the karaoke highlight span so the outline
            // stays uniformly black; the fill pass below draws the highlight.
            val strokeLayout = StaticLayout.Builder
                .obtain(SpannableString(text), 0, text.length, paint, maxWidthPx)
                .setAlignment(Layout.Alignment.ALIGN_CENTER)
                .setIncludePad(true)
                .build()
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = strokePx
            paint.color = Color.BLACK
            canvas.save()
            canvas.translate(renderWidth / 2f, anchorY - strokeLayout.height / 2f)
            strokeLayout.draw(canvas)
            canvas.restore()
            paint.style = Paint.Style.FILL
            paint.color = captionStyle.color
        }

        canvas.save()
        canvas.translate(renderWidth / 2f, anchorY - fillLayout.height / 2f)
        fillLayout.draw(canvas)
        canvas.restore()
        return bitmap
    }

    private fun activeWordIndex(
        cue: CaptionCueDescriptor,
        clipStartMs: Long,
        presentationTimeUs: Long
    ): Int {
        val timelineMs = clipStartMs + presentationTimeUs / 1_000
        return cue.words.indexOfFirst { timelineMs >= it.startMs && timelineMs < it.endMs }
    }

    private fun karaokeSpannable(
        text: String,
        cue: CaptionCueDescriptor?,
        activeWordIndex: Int
    ): SpannableString {
        val spannable = SpannableString(text)
        if (!captionStyle.karaoke || cue == null || activeWordIndex !in cue.words.indices) {
            return spannable
        }
        val range = wordRange(text, cue, activeWordIndex)
        if (range.first < range.second) {
            spannable.setSpan(
                ForegroundColorSpan(captionStyle.highlightColor),
                range.first,
                range.second,
                SpannableString.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        return spannable
    }

    /**
     * Locates the character range of the active word inside [text] by walking
     * the preceding words. Words are expected to be joined by single spaces;
     * when the active word cannot be located (e.g. the text was edited after
     * transcription), the highlight is skipped gracefully.
     */
    private fun wordRange(
        text: String,
        cue: CaptionCueDescriptor,
        wordIndex: Int
    ): Pair<Int, Int> {
        var offset = 0
        for (i in 0 until wordIndex) {
            val word = cue.words[i].text.uppercase()
            if (word.isEmpty()) continue
            val found = text.indexOf(word, offset)
            if (found == -1) return Pair(0, 0)
            offset = found + word.length
            if (offset < text.length && text[offset] == ' ') {
                offset++
            }
        }
        val activeWord = cue.words[wordIndex].text.uppercase()
        val found = text.indexOf(activeWord, offset)
        if (found == -1) return Pair(0, 0)
        return Pair(found, found + activeWord.length)
    }
}
