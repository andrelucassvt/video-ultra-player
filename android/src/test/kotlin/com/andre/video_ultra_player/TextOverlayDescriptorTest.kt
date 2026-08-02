package com.andre.video_ultra_player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class TextOverlayDescriptorTest {

    private fun fullMap() = mapOf(
        "id" to "text-1",
        "text" to "Hello\nWorld",
        "startMs" to 500L,
        "endMs" to 3_000L,
        "x" to 0.25,
        "y" to 0.75,
        "rotationDegrees" to 15,
        "fontSize" to 0.08,
        "color" to 0xFFFF0000,
        "fontFamily" to "Avenir",
        "fontPath" to "/fonts/custom.otf",
        "backgroundColor" to 0x80000000,
        "opacity" to 0.5,
        "textAlign" to "right"
    )

    @Test
    fun from_parsesAllContractFields() {
        val descriptor = TextOverlayDescriptor.from(fullMap())

        assertEquals("text-1", descriptor.id)
        assertEquals("Hello\nWorld", descriptor.text)
        assertEquals(500L, descriptor.startMs)
        assertEquals(3_000L, descriptor.endMs)
        assertEquals(0.25, descriptor.x)
        assertEquals(0.75, descriptor.y)
        assertEquals(15.0, descriptor.rotationDegrees)
        assertEquals(0.08, descriptor.fontSize)
        assertEquals(0xFFFF0000.toInt(), descriptor.color)
        assertEquals("Avenir", descriptor.fontFamily)
        assertEquals("/fonts/custom.otf", descriptor.fontPath)
        assertEquals(0x80000000.toInt(), descriptor.backgroundColor)
        assertEquals(0.5, descriptor.opacity)
        assertEquals(TextOverlayTextAlign.RIGHT, descriptor.textAlign)
    }

    @Test
    fun from_appliesDefaults() {
        val descriptor = TextOverlayDescriptor.from(
            mapOf("id" to "t", "text" to "Hi", "startMs" to 0L, "endMs" to 1_000L)
        )

        assertEquals(TextOverlayTextAlign.CENTER, descriptor.textAlign)
        assertEquals(1.0, descriptor.opacity)
        assertEquals(0.5, descriptor.x)
        assertEquals(0.5, descriptor.y)
        assertEquals(0.0, descriptor.rotationDegrees)
        assertEquals(0xFFFFFFFF.toInt(), descriptor.color)
        assertEquals(0, descriptor.backgroundColor)
    }

    @Test
    fun from_throwsWhenIdOrTextMissing() {
        assertFailsWith<IllegalStateException> {
            TextOverlayDescriptor.from(
                mapOf("text" to "Hi", "startMs" to 0L, "endMs" to 1_000L)
            )
        }
        assertFailsWith<IllegalStateException> {
            TextOverlayDescriptor.from(
                mapOf("id" to "t", "startMs" to 0L, "endMs" to 1_000L)
            )
        }
    }

    @Test
    fun from_clampsPositionSizeAndOpacity() {
        val descriptor = TextOverlayDescriptor.from(
            mapOf(
                "id" to "t",
                "text" to "Hi",
                "startMs" to 0L,
                "endMs" to 1_000L,
                "x" to -1.0,
                "y" to 2.0,
                "fontSize" to 0.0,
                "opacity" to 1.5
            )
        )

        assertEquals(0.0, descriptor.x)
        assertEquals(1.0, descriptor.y)
        assertTrue(descriptor.fontSize > 0.0 && descriptor.fontSize <= 1.0)
        assertEquals(1.0, descriptor.opacity)
    }

    @Test
    fun textOverlaysForClip_keepsOverlayFullyInsideClip() {
        val overlay = TextOverlayDescriptor.from(
            mapOf(
                "id" to "t",
                "text" to "Hi",
                "startMs" to 500L,
                "endMs" to 1_500L
            )
        )

        val result = textOverlaysForClip(listOf(overlay), clipStartMs = 0L, clipDurationMs = 2_000L)

        assertEquals(1, result.size)
        assertEquals(500L, result[0].startMs)
        assertEquals(1_500L, result[0].endMs)
    }

    @Test
    fun textOverlaysForClip_reanchorsAndClampsPartialOverlap() {
        val overlay = TextOverlayDescriptor.from(
            mapOf(
                "id" to "t",
                "text" to "Hi",
                "startMs" to 500L,
                "endMs" to 4_000L
            )
        )

        // Clip covers [1_000, 3_000); overlay covers [500, 4_000).
        val result = textOverlaysForClip(listOf(overlay), clipStartMs = 1_000L, clipDurationMs = 2_000L)

        assertEquals(1, result.size)
        // Re-anchored: window relative to clip start, clamped to clip duration.
        assertEquals(0L, result[0].startMs)
        assertEquals(2_000L, result[0].endMs)
    }

    @Test
    fun textOverlaysForClip_dropsOverlaysOutsideClipWindow() {
        val before = TextOverlayDescriptor.from(
            mapOf("id" to "a", "text" to "A", "startMs" to 0L, "endMs" to 500L)
        )
        val after = TextOverlayDescriptor.from(
            mapOf("id" to "b", "text" to "B", "startMs" to 4_000L, "endMs" to 5_000L)
        )

        val result = textOverlaysForClip(
            listOf(before, after),
            clipStartMs = 1_000L,
            clipDurationMs = 2_000L
        )

        assertTrue(result.isEmpty())
    }

    @Test
    fun textOverlaysForClip_clampsEndToClipEnd() {
        val overlay = TextOverlayDescriptor.from(
            mapOf(
                "id" to "t",
                "text" to "Hi",
                "startMs" to 1_500L,
                "endMs" to 10_000L
            )
        )

        val result = textOverlaysForClip(listOf(overlay), clipStartMs = 1_000L, clipDurationMs = 2_000L)

        assertEquals(1, result.size)
        assertEquals(500L, result[0].startMs)
        assertEquals(2_000L, result[0].endMs)
    }

    @Test
    fun textOverlaysForClip_dropsOverlayEndingExactlyAtClipStart() {
        val overlay = TextOverlayDescriptor.from(
            mapOf("id" to "t", "text" to "Hi", "startMs" to 0L, "endMs" to 1_000L)
        )

        val result = textOverlaysForClip(listOf(overlay), clipStartMs = 1_000L, clipDurationMs = 2_000L)

        assertTrue(result.isEmpty())
    }

    @Test
    fun editSnapshot_roundTripsTextOverlays() {
        val clip = TimelineClip(
            path = "/tmp/a.mp4",
            type = TimelineMediaType.VIDEO,
            durationMs = 2_000L,
            alignmentX = 0.0,
            alignmentY = 0.0,
            scale = 1.0
        )
        val overlay = TextOverlayDescriptor.from(
            mapOf("id" to "t", "text" to "Hi", "startMs" to 100L, "endMs" to 900L)
        )
        val snapshot = TimelineEditSnapshot(
            clips = listOf(clip),
            audioTrack = null,
            textOverlays = listOf(overlay)
        )

        val copy = snapshot.copy(
            clips = snapshot.clips,
            audioTrack = snapshot.audioTrack,
            textOverlays = snapshot.textOverlays
        )

        assertEquals(snapshot.textOverlays, copy.textOverlays)
        assertFalse(copy.textOverlays.isEmpty())
        assertEquals("t", copy.textOverlays[0].id)
        assertEquals(100L, copy.textOverlays[0].startMs)
    }
}
