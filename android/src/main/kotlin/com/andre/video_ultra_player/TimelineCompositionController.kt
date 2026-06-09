@file:OptIn(UnstableApi::class)

package com.andre.video_ultra_player

import android.content.Context
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
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Crop
import androidx.media3.transformer.Composition
import androidx.media3.transformer.CompositionPlayer
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.io.File
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

private const val DEFAULT_WIDTH = 1280
private const val DEFAULT_HEIGHT = 720
private const val DEFAULT_IMAGE_DURATION_MS = 2_000L
private const val STATE_INTERVAL_MS = 33L

internal class TimelineCompositionController(
    private val context: Context,
    private val textureRegistry: TextureRegistry
) {
    private var clips: MutableList<TimelineClip> = mutableListOf()
    private var segments: List<TimelineSegment> = emptyList()
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

    fun load(rawClips: List<*>): Long {
        require(rawClips.isNotEmpty()) { "Timeline must contain at least one clip." }

        clips = rawClips.map { raw ->
            TimelineClip.from(raw as? Map<*, *> ?: error("Invalid timeline clip."))
        }.toMutableList()
        rebuildSegments()

        val entry = textureRegistry.createSurfaceTexture()
        entry.surfaceTexture().setDefaultBufferSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
        val renderSurface = Surface(entry.surfaceTexture())

        textureEntry = entry
        surface = renderSurface

        player = CompositionPlayer.Builder(context)
            .build()
            .also { compositionPlayer ->
                compositionPlayer.setVideoSurface(
                    renderSurface,
                    Size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
                )
                compositionPlayer.addListener(
                    object : Player.Listener {
                        override fun onPlayerError(error: PlaybackException) {
                            eventSink?.error(
                                "playback_error",
                                error.message ?: "CompositionPlayer playback failed.",
                                null
                            )
                        }
                    }
                )
                compositionPlayer.setComposition(buildComposition())
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

        val currentPlayer = player ?: return
        val positionMs = currentPlayer.currentPosition.coerceAtLeast(0L)
        val wasPlaying = currentPlayer.isPlaying
        // Media3 effects are immutable, so live pan/crop is applied by rebuilding the Composition.
        currentPlayer.setComposition(buildComposition(), positionMs)
        currentPlayer.prepare()
        if (wasPlaying) {
            currentPlayer.play()
        }
        emitState()
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

    private fun buildComposition(): Composition {
        val editedItems = clips.map { clip ->
            val mediaItemBuilder = MediaItem.Builder()
                .setUri(Uri.fromFile(File(clip.path)))

            if (clip.type == TimelineMediaType.IMAGE) {
                mediaItemBuilder.setImageDurationMs(clip.resolvedDurationMs)
            }

            val builder = EditedMediaItem.Builder(mediaItemBuilder.build())
                .setDurationUs(clip.resolvedDurationMs * 1_000L)
                .setEffects(effectsFor(clip))

            if (clip.type == TimelineMediaType.IMAGE) {
                builder.setFrameRate(30)
            }

            builder.build()
        }
        val sequence = EditedMediaItemSequence.withAudioAndVideoFrom(editedItems)
        return Composition.Builder(listOf(sequence)).build()
    }

    private fun effectsFor(clip: TimelineClip): Effects {
        val scale = max(clip.scale, 1.0)
        if (scale <= 1.0001) {
            return Effects.EMPTY
        }

        val visibleSpan = (2.0 / scale).coerceIn(0.05, 2.0).toFloat()
        val extraSpan = 2.0f - visibleSpan
        val horizontalBias = ((clip.alignmentX + 1.0) / 2.0).toFloat()
        val verticalBias = ((clip.alignmentY + 1.0) / 2.0).toFloat()
        val left = -1.0f + extraSpan * horizontalBias
        val right = left + visibleSpan
        val top = 1.0f - extraSpan * verticalBias
        val bottom = top - visibleSpan

        val effects = listOf<Effect>(
            Crop(
                min(left, right - 0.01f),
                max(right, left + 0.01f),
                min(bottom, top - 0.01f),
                max(top, bottom + 0.01f)
            )
        )
        return Effects(emptyList(), effects)
    }

    private fun rebuildSegments() {
        var startMs = 0L
        segments = clips.map { clip ->
            clip.resolvedDurationMs = resolveDurationMs(clip)
            TimelineSegment(
                startMs = startMs,
                durationMs = clip.resolvedDurationMs
            ).also {
                startMs += clip.resolvedDurationMs
            }
        }
        totalDurationMs = startMs
    }

    private fun resolveDurationMs(clip: TimelineClip): Long {
        clip.durationMs?.let {
            return max(it, 1L)
        }

        if (clip.type == TimelineMediaType.IMAGE) {
            return DEFAULT_IMAGE_DURATION_MS
        }

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(clip.path)
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()
                ?.let { max(it, 1L) }
                ?: DEFAULT_IMAGE_DURATION_MS
        } finally {
            retriever.release()
        }
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
                "totalDuration" to totalDurationMs
            )
        )
    }

    private fun segmentIndexFor(positionMs: Long): Int {
        if (segments.isEmpty()) {
            return 0
        }

        val index = segments.indexOfFirst { segment ->
            positionMs >= segment.startMs && positionMs < segment.startMs + segment.durationMs
        }
        return if (index >= 0) index else segments.lastIndex
    }
}

private data class TimelineSegment(
    val startMs: Long,
    val durationMs: Long
)

private data class TimelineClip(
    val path: String,
    val type: TimelineMediaType,
    val durationMs: Long?,
    val alignmentX: Double,
    val alignmentY: Double,
    val scale: Double,
    var resolvedDurationMs: Long = 0L
) {
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

            return TimelineClip(
                path = path,
                type = type,
                durationMs = durationMs,
                alignmentX = alignmentX,
                alignmentY = alignmentY,
                scale = max(scale, 0.01)
            )
        }
    }
}

private enum class TimelineMediaType {
    VIDEO,
    IMAGE
}
