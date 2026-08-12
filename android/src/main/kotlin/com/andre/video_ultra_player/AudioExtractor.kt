package com.andre.video_ultra_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID

private const val AUDIO_EXPORT_PROGRESS_INTERVAL_MS = 100L

/**
 * Extracts the audio of a composed timeline as an m4a (AAC) file, keeping
 * trims, speeds and gaps of the composition. The output feeds speech
 * recognition — the current implementation preserves the source sample rate
 * and channel layout.
 */
internal class AudioExtractor(
    private val context: Context
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var completed = false
    private val progressHolder = ProgressHolder()
    private var progressCallback: TimelineExportCallback? = null
    private val progressRunnable = object : Runnable {
        override fun run() {
            val activeTransformer = transformer
            val callback = progressCallback
            if (activeTransformer != null && callback != null && !completed) {
                val state = activeTransformer.getProgress(progressHolder)
                val progress = if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    progressHolder.progress.coerceIn(0, 100) / 100.0
                } else {
                    0.0
                }
                callback.onProgress(progress, "exporting")
                mainHandler.postDelayed(this, AUDIO_EXPORT_PROGRESS_INTERVAL_MS)
            }
        }
    }

    fun extract(
        clips: List<TimelineClip>,
        outputPath: String?,
        callback: TimelineExportCallback
    ) {
        progressCallback = callback
        callback.onProgress(0.0, "exporting")
        val outputFile = audioOutputFile(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val composition = buildAudioOnlyComposition(clips)
        val audioTransformer = Transformer.Builder(context)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
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

        transformer = audioTransformer
        audioTransformer.start(composition, outputFile.absolutePath)
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

    private fun buildAudioOnlyComposition(clips: List<TimelineClip>): Composition {
        val items = clips
            .filter { it.type == TimelineMediaType.VIDEO }
            .map { audioOnlyItemFor(it) }
        val sequenceBuilder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
        items.forEach { sequenceBuilder.addItem(it) }
        return Composition.Builder(listOf(sequenceBuilder.build())).build()
    }

    private fun audioOnlyItemFor(clip: TimelineClip): EditedMediaItem {
        val mediaItemBuilder = MediaItem.Builder()
            .setUri(Uri.fromFile(File(clip.path)))
        if (clip.trimStartMs != null || clip.trimEndMs != null) {
            val clippingBuilder = MediaItem.ClippingConfiguration.Builder()
            clip.trimStartMs?.let { clippingBuilder.setStartPositionMs(it) }
            clip.trimEndMs?.let { clippingBuilder.setEndPositionMs(it) }
            mediaItemBuilder.setClippingConfiguration(clippingBuilder.build())
        }

        // setDurationUs must be the full source duration (not the trimmed one)
        // because Media3 validates that clippingEndPositionMs * 1000 <= durationUs.
        val sourceDurationUs = if (clip.sourceDurationMs > 0) {
            clip.sourceDurationMs * 1_000L
        } else {
            (clip.durationMs ?: 2_000L) * 1_000L
        }
        val builder = EditedMediaItem.Builder(mediaItemBuilder.build())
            .setRemoveVideo(true)
            .setDurationUs(sourceDurationUs)
        if (clip.speed != 1.0f) {
            builder.setSpeed(constantSpeedProvider(clip.speed))
        }
        return builder.build()
    }

    private fun audioOutputFile(outputPath: String?): File {
        if (!outputPath.isNullOrBlank()) {
            return File(outputPath)
        }
        return File(
            context.cacheDir,
            "video_ultra_player_audio_${UUID.randomUUID()}.m4a"
        )
    }
}
