package com.andre.video_ultra_player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class CaptionOverlayTest {

    private fun cue(id: String, startMs: Long, endMs: Long): CaptionCueDescriptor {
        return CaptionCueDescriptor(
            text = "Cue $id",
            startMs = startMs,
            endMs = endMs,
            words = emptyList()
        )
    }

    @Test
    fun activeCaptionCue_returnsCueContainingTheTime() {
        val cues = listOf(
            cue("a", 0L, 1_000L),
            cue("b", 1_000L, 2_500L)
        )

        assertEquals("Cue a", activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 500_000L)?.text)
        assertEquals("Cue b", activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 2_000_000L)?.text)
    }

    @Test
    fun activeCaptionCue_returnsNullOutsideAnyWindow() {
        val cues = listOf(
            cue("a", 1_000L, 2_000L),
            cue("b", 3_000L, 4_000L)
        )

        assertNull(activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 500_000L))
        assertNull(activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 2_500_000L))
        assertNull(activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 5_000_000L))
    }

    @Test
    fun activeCaptionCue_firstCueWinsWhenWindowsTouchExactlyAtTheBoundary() {
        val cues = listOf(
            cue("a", 0L, 1_500L),
            cue("b", 1_000L, 2_000L)
        )

        // t = 1000 belongs to both windows; the first cue wins.
        assertEquals("Cue a", activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 1_000_000L)?.text)
        // t = 1500 is exactly the end of a's window (exclusive) — b wins.
        assertEquals("Cue b", activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 1_500_000L)?.text)
    }

    @Test
    fun activeCaptionCue_acceptsWindowExactlyAtClipStart() {
        val cues = listOf(cue("a", 0L, 1_000L))

        assertEquals("Cue a", activeCaptionCue(cues, clipStartMs = 0L, presentationTimeUs = 0L)?.text)
    }

    @Test
    fun activeCaptionCue_offsetsPresentationTimeByClipStart() {
        val cues = listOf(cue("a", 1_500L, 2_500L))

        // Clip starts at 1s; presentation time is clip-local, so the cue's
        // timeline window [1500, 2500) matches presentation [500, 1500).
        assertEquals("Cue a", activeCaptionCue(cues, clipStartMs = 1_000L, presentationTimeUs = 1_000_000L)?.text)
        assertNull(activeCaptionCue(cues, clipStartMs = 1_000L, presentationTimeUs = 400_000L))
    }
}
