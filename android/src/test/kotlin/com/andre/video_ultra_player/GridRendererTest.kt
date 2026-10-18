package com.andre.video_ultra_player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class GridRendererTest {
    private fun rawGrid(cells: List<Map<String, Any>>) = mapOf(
        "width" to 1080,
        "height" to 1920,
        "cells" to cells,
        "overlayImagePath" to "/overlay.png",
        "audioCellIndex" to 1,
        "maxDurationMs" to 30_000
    )

    private val top = mapOf("path" to "/a.mp4", "x" to 0.0, "y" to 0.0, "width" to 1.0, "height" to 0.5)
    private val bottom = mapOf("path" to "/b.mp4", "x" to 0.0, "y" to 0.5, "width" to 1.0, "height" to 0.5)

    @Test
    fun descriptor_parsesTheDartPayload() {
        val grid = assertNotNull(GridCompositionDescriptor.from(rawGrid(listOf(top, bottom))))

        assertEquals(1080, grid.width)
        assertEquals(1920, grid.height)
        assertEquals(2, grid.cells.size)
        assertEquals("/b.mp4", grid.cells[1].path)
        assertEquals("/overlay.png", grid.overlayImagePath)
        assertEquals(1, grid.audioCellIndex)
        assertEquals(30_000L, grid.maxDurationMs)
    }

    @Test
    fun descriptor_rejectsInvalidCells() {
        assertNull(GridCompositionDescriptor.from(rawGrid(emptyList())))
        assertNull(GridCompositionDescriptor.from(rawGrid(listOf(top + ("width" to 0.0)))))
        assertNull(GridCompositionDescriptor.from(null))
    }

    @Test
    fun cellCenterNdc_flipsYToPointUp() {
        val grid = assertNotNull(GridCompositionDescriptor.from(rawGrid(listOf(top, bottom))))

        assertEquals(0f to 0.5f, cellCenterNdc(grid.cells[0]))
        assertEquals(0f to -0.5f, cellCenterNdc(grid.cells[1]))
    }

    @Test
    fun cellPixelSize_isEvenAndCoversTheCell() {
        val grid = assertNotNull(
            GridCompositionDescriptor.from(
                rawGrid(listOf(mapOf("path" to "/a.mp4", "x" to 0.0, "y" to 0.0, "width" to 1.0 / 3.0, "height" to 0.5)))
                    .plus("width" to 1081)
            )
        )
        val size = cellPixelSize(grid, grid.cells[0])

        assertEquals(360, size.width)
        assertEquals(960, size.height)
    }
}
