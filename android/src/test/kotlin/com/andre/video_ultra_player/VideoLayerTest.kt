package com.andre.video_ultra_player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class VideoLayerTest {

    private fun fullMap() = mapOf(
        "id" to "a",
        "path" to "/v.mp4",
        "startMs" to 1_500L,
        "trimStartMs" to 200L,
        "trimEndMs" to 4_200L,
        "x" to 0.25,
        "y" to 0.75,
        "widthFraction" to 0.4,
        "opacity" to 1.0
    )

    private fun layer(
        startMs: Long = 1_500L,
        trimStartMs: Long = 200L,
        trimEndMs: Long? = 4_200L
    ) = VideoLayerDescriptor(
        id = "a",
        path = "/v.mp4",
        startMs = startMs,
        trimStartMs = trimStartMs,
        trimEndMs = trimEndMs,
        x = 0.5,
        y = 0.5,
        widthFraction = 0.5,
        opacity = 0.8
    )

    @Test
    fun from_parsesAllContractFields() {
        val descriptor = VideoLayerDescriptor.from(fullMap())

        assertEquals("a", descriptor.id)
        assertEquals("/v.mp4", descriptor.path)
        assertEquals(1_500L, descriptor.startMs)
        assertEquals(200L, descriptor.trimStartMs)
        assertEquals(4_200L, descriptor.trimEndMs)
        assertEquals(0.25, descriptor.x)
        assertEquals(0.75, descriptor.y)
        assertEquals(0.4, descriptor.widthFraction)
        assertEquals(1.0, descriptor.opacity)
    }

    @Test
    fun toMap_roundTripsTheContractMap() {
        assertEquals(fullMap(), VideoLayerDescriptor.from(fullMap()).toMap())
    }

    @Test
    fun from_withoutTrimEnd_leavesItNull() {
        val descriptor = VideoLayerDescriptor.from(fullMap() - "trimEndMs")

        assertNull(descriptor.trimEndMs)
        assertEquals(false, descriptor.toMap().containsKey("trimEndMs"))
    }

    @Test
    fun visibleWindow_insideTimeline_isStartPlusTrimmedLength() {
        assertEquals(1_500L..5_500L, layer().visibleWindowMs(6_000L, 10_000L))
    }

    @Test
    fun visibleWindow_pastTimelineEnd_isClampedToTheEnd() {
        assertEquals(1_500L..3_000L, layer().visibleWindowMs(6_000L, 3_000L))
    }

    @Test
    fun visibleWindow_startingAfterTimelineEnd_isNull() {
        assertNull(layer(startMs = 12_000L).visibleWindowMs(6_000L, 10_000L))
    }

    @Test
    fun visibleWindow_withoutTrimEnd_runsToTheSourceEnd() {
        assertEquals(
            1_500L..7_300L,
            layer(trimEndMs = null).visibleWindowMs(6_000L, 10_000L)
        )
    }

    @Test
    fun videoSequenceOrder_putsTheLastLayerOnTopAndTheMainLast() {
        assertEquals(listOf(-1), videoSequenceOrder(0))
        assertEquals(listOf(1, 0, -1), videoSequenceOrder(2))
        assertEquals(listOf(2, 1, 0, -1), videoSequenceOrder(3))
    }

    @Test
    fun layerPixelSize_followsWidthFractionAndSourceAspect() {
        val size = layerPixelSize(
            widthFraction = 0.5,
            sourceWidth = 1080,
            sourceHeight = 1920,
            renderSize = TimelineRenderSize(1080, 1920)
        )

        assertEquals(540, size.width)
        assertEquals(960, size.height)
    }

    @Test
    fun layerAnchorNdc_flipsYToPointUp() {
        assertEquals(-0.5f to 0.5f, layerAnchorNdc(0.25, 0.25))
        assertEquals(0f to 0f, layerAnchorNdc(0.5, 0.5))
    }

    @Test
    fun compositorSettings_keepLayerOpacityAtAnyTimestamp() {
        val settings = VideoLayerCompositorSettings(
            renderSize = TimelineRenderSize(1080, 1920),
            layersBySequence = mapOf(0 to PlacedVideoLayer(layer(), 1_500L..5_500L))
        )

        // Preview timestamps can be offset: the filler stills hide the layer
        // outside its window, so the alpha must never depend on time.
        assertEquals(0.8f, settings.getOverlaySettings(0, 1_000_000L).alphaScale)
        assertEquals(0.8f, settings.getOverlaySettings(0, 2_000_000L).alphaScale)
        assertEquals(0.8f, settings.getOverlaySettings(0, 1_000_000_000_000L).alphaScale)
        // The main sequence is drawn at full opacity, untouched.
        assertEquals(1f, settings.getOverlaySettings(1, 2_000_000L).alphaScale)
        assertEquals(1080, settings.getOutputSize(emptyList()).width)
    }

    @Test
    fun layerSequence_padsWithInvisibleClipsOfTheSameVideo() {
        val placed = PlacedVideoLayer(
            layer().copy(sourceDurationMs = 6_000L, sourceWidth = 1080, sourceHeight = 1920),
            1_500L..5_500L
        )

        val items = videoLayerSequence(placed, TimelineRenderSize(1080, 1920), 10_000L)
            .editedMediaItems

        // Gaps stall seeks and an image→video switch inside the primary
        // multi-input sequence freezes the preview: padding must be video.
        assertEquals(
            listOf(LAYER_FILLER_MEDIA_ID, "", LAYER_FILLER_MEDIA_ID),
            items.map { if (it.mediaItem.mediaId == LAYER_FILLER_MEDIA_ID) it.mediaItem.mediaId else "" }
        )
        assertEquals(false, items.any { it.mediaItem.mediaId == "androidx-media3-GapMediaItem" })
        assertEquals(1_500L, items[0].mediaItem.clippingConfiguration.endPositionMs)
        assertEquals(4_500L, items[2].mediaItem.clippingConfiguration.endPositionMs)
    }

    @Test
    fun layerSequence_paddingLongerThanTheSource_isSplitIntoClips() {
        val placed = PlacedVideoLayer(
            layer(startMs = 2_500L, trimStartMs = 0L, trimEndMs = 1_000L)
                .copy(sourceDurationMs = 1_000L),
            2_500L..3_500L
        )

        val items = videoLayerSequence(placed, TimelineRenderSize(1080, 1920), 3_500L)
            .editedMediaItems

        // 2,5 s of padding from a 1 s source: 1 s + 1 s + 0,5 s, then the layer.
        assertEquals(
            listOf(1_000L, 1_000L, 500L),
            items.take(3).map { it.mediaItem.clippingConfiguration.endPositionMs }
        )
        assertEquals(4, items.size)
    }

    @Test
    fun layerSequence_startingAtZeroAndRunningToTheEnd_hasNoFiller() {
        val placed = PlacedVideoLayer(
            layer(startMs = 0L, trimStartMs = 0L, trimEndMs = 10_000L).copy(
                sourceDurationMs = 10_000L
            ),
            0L..10_000L
        )

        val items = videoLayerSequence(placed, TimelineRenderSize(1080, 1920), 10_000L)
            .editedMediaItems

        assertEquals(1, items.size)
    }
}
