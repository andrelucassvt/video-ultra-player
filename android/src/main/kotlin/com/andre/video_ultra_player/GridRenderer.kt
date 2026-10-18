package com.andre.video_ultra_player

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoCompositorSettings
import androidx.media3.common.util.Size
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

private const val GRID_FRAME_RATE = 30

/** One video cell; the rect is normalized to the canvas with top-left origin. */
internal data class GridCellDescriptor(
    val path: String,
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double
) {
    companion object {
        fun from(map: Map<*, *>): GridCellDescriptor? {
            val path = map["path"] as? String ?: return null
            val x = (map["x"] as? Number)?.toDouble() ?: return null
            val y = (map["y"] as? Number)?.toDouble() ?: return null
            val width = (map["width"] as? Number)?.toDouble() ?: return null
            val height = (map["height"] as? Number)?.toDouble() ?: return null
            if (width <= 0.0 || height <= 0.0) return null
            return GridCellDescriptor(path, x, y, width, height)
        }
    }
}

internal data class GridCompositionDescriptor(
    val width: Int,
    val height: Int,
    val cells: List<GridCellDescriptor>,
    val overlayImagePath: String?,
    val audioCellIndex: Int?,
    val maxDurationMs: Long?
) {
    companion object {
        fun from(map: Map<*, *>?): GridCompositionDescriptor? {
            if (map == null) return null
            val width = (map["width"] as? Number)?.toInt() ?: return null
            val height = (map["height"] as? Number)?.toInt() ?: return null
            val rawCells = map["cells"] as? List<*> ?: return null
            if (width <= 0 || height <= 0 || rawCells.isEmpty()) return null
            val cells = rawCells.mapNotNull { (it as? Map<*, *>)?.let(GridCellDescriptor::from) }
            if (cells.size != rawCells.size) return null
            return GridCompositionDescriptor(
                width = width,
                height = height,
                cells = cells,
                overlayImagePath = (map["overlayImagePath"] as? String)?.takeIf { it.isNotBlank() },
                audioCellIndex = (map["audioCellIndex"] as? Number)?.toInt(),
                maxDurationMs = (map["maxDurationMs"] as? Number)?.toLong()?.takeIf { it > 0 }
            )
        }
    }
}

/** Blocking source facts resolved before the composition is assembled. */
internal data class GridSourceInfo(
    val durationsMs: List<Long>,
    val audioCellHasAudio: Boolean,
    val overlayPath: String
)

/**
 * Builds the Media3 composition of a split-screen grid.
 *
 * Sequence 0 is the overlay PNG (background, cell shapes and still images):
 * it is the only non-looping sequence, so its duration defines the output
 * length, and the compositor draws input 0 on top with alpha blending. Every
 * video cell is its own looping sequence, pre-scaled by [Presentation] to cover
 * its cell and positioned by [VideoCompositorSettings].
 */
internal object GridRenderer {
    /**
     * Blocking work (metadata reads, writing the fallback overlay). Must run
     * off the main thread.
     */
    fun resolveSources(context: Context, grid: GridCompositionDescriptor): GridSourceInfo {
        val durations = grid.cells.map { cell ->
            SourceMetadataCache.get(context, cell.path, TimelineMediaType.VIDEO).durationMs
        }
        val audioCell = grid.audioCellIndex?.let { grid.cells.getOrNull(it) }
        val hasAudio = audioCell != null && hasAudioTrack(context, audioCell.path)
        val overlayPath = grid.overlayImagePath ?: transparentOverlay(context, grid)
        return GridSourceInfo(durations, hasAudio, overlayPath)
    }

    fun buildComposition(
        grid: GridCompositionDescriptor,
        sources: GridSourceInfo
    ): Composition {
        val longestMs = sources.durationsMs.maxOrNull() ?: 0L
        val totalMs = grid.maxDurationMs?.let { min(it, longestMs) } ?: longestMs
        require(totalMs > 0L) { "Grid has no playable duration." }

        val overlayItem = EditedMediaItem.Builder(
            MediaItem.Builder()
                .setUri(Uri.fromFile(File(sources.overlayPath)))
                .setImageDurationMs(totalMs)
                .build()
        )
            .setDurationUs(totalMs * 1_000L)
            .setFrameRate(GRID_FRAME_RATE)
            .build()
        val sequences = mutableListOf(
            EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_VIDEO))
                .addItem(overlayItem)
                .build()
        )

        grid.cells.forEachIndexed { index, cell ->
            val sourceDurationMs = sources.durationsMs[index]
            val keepsAudio = index == grid.audioCellIndex && sources.audioCellHasAudio
            val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(File(cell.path)))
            if (sourceDurationMs > totalMs) {
                mediaItemBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setEndPositionMs(totalMs)
                        .build()
                )
            }
            val cellSize = cellPixelSize(grid, cell)
            val item = EditedMediaItem.Builder(mediaItemBuilder.build())
                .setDurationUs(sourceDurationMs * 1_000L)
                .setRemoveAudio(!keepsAudio)
                .setEffects(
                    Effects(
                        emptyList(),
                        listOf(
                            Presentation.createForWidthAndHeight(
                                cellSize.width,
                                cellSize.height,
                                Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                            )
                        )
                    )
                )
                .build()
            val trackTypes = if (keepsAudio) {
                setOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO)
            } else {
                setOf(C.TRACK_TYPE_VIDEO)
            }
            sequences.add(
                EditedMediaItemSequence.Builder(trackTypes)
                    .addItem(item)
                    .setIsLooping(true)
                    .build()
            )
        }

        return Composition.Builder(sequences)
            .setVideoCompositorSettings(GridCompositorSettings(grid))
            .build()
    }

    private fun hasAudioTrack(context: Context, path: String): Boolean {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, Uri.fromFile(File(path)))
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
        } catch (error: Throwable) {
            false
        } finally {
            retriever.release()
        }
    }

    /**
     * Without a caller overlay the grid still needs a non-looping input that
     * defines its length and keeps the multi-input compositor engaged.
     */
    private fun transparentOverlay(context: Context, grid: GridCompositionDescriptor): String {
        val file = File(context.cacheDir, "video_ultra_player_grid_${grid.width}x${grid.height}.png")
        if (!file.exists()) {
            val bitmap = Bitmap.createBitmap(grid.width, grid.height, Bitmap.Config.ARGB_8888)
            FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
        return file.absolutePath
    }
}

internal fun cellPixelSize(grid: GridCompositionDescriptor, cell: GridCellDescriptor): Size {
    return Size(
        evenAtLeastTwo(cell.width * grid.width),
        evenAtLeastTwo(cell.height * grid.height)
    )
}

private fun evenAtLeastTwo(value: Double): Int {
    val rounded = max(value.roundToInt(), 2)
    return if (rounded % 2 == 0) rounded else rounded - 1
}

/**
 * Places every cell at its normalized center. Anchors are in NDC (y up), and
 * the compositor draws each input at its own pixel size, which [Presentation]
 * already made equal to the cell.
 */
internal class GridCompositorSettings(
    private val grid: GridCompositionDescriptor
) : VideoCompositorSettings {
    override fun getOutputSize(inputSizes: List<Size>): Size = Size(grid.width, grid.height)

    override fun getOverlaySettings(inputId: Int, presentationTimeUs: Long): OverlaySettings {
        val cell = grid.cells.getOrNull(inputId - 1)
            ?: return StaticOverlaySettings.Builder().build()
        val (centerX, centerY) = cellCenterNdc(cell)
        return StaticOverlaySettings.Builder()
            .setBackgroundFrameAnchor(centerX, centerY)
            .build()
    }
}

/** Cell center in normalized device coordinates: x right, y up, both in [-1, 1]. */
internal fun cellCenterNdc(cell: GridCellDescriptor): Pair<Float, Float> {
    val centerX = (cell.x + cell.width / 2.0) * 2.0 - 1.0
    val centerY = 1.0 - (cell.y + cell.height / 2.0) * 2.0
    return centerX.toFloat() to centerY.toFloat()
}
