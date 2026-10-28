package com.andre.video_ultra_player

import androidx.media3.common.C
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

    @Test
    fun compositorSettings_liveUpdateMovesAndScalesWithoutRebuild() {
        val baked = layer()
        val settings = VideoLayerCompositorSettings(
            renderSize = TimelineRenderSize(1080, 1920),
            layersBySequence = mapOf(0 to PlacedVideoLayer(baked, 1_500L..5_500L))
        )

        settings.updatePlacement(baked.copy(x = 0.25, y = 0.25, widthFraction = 0.75, opacity = 0.5))

        // Same anchor math as layerAnchorNdc; size relative to the baked 0.5.
        assertEquals(
            LayerOverlayPlacement(
                anchorX = -0.5f,
                anchorY = 0.5f,
                scaleX = 1.5f,
                scaleY = 1.5f,
                alpha = 0.5f
            ),
            settings.placementFor(0)
        )
        assertEquals(null, settings.placementFor(1))
    }

    @Test
    fun compositorSettings_liveUpdateForAnotherLayer_isIgnored() {
        val settings = VideoLayerCompositorSettings(
            renderSize = TimelineRenderSize(1080, 1920),
            layersBySequence = mapOf(0 to PlacedVideoLayer(layer(), 1_500L..5_500L))
        )

        settings.updatePlacement(layer().copy(id = "other", x = 0.1))

        assertEquals(0f, settings.placementFor(0)?.anchorX)
    }

    @Test
    fun layerPixelSize_withHeightFraction_stretchesIndependently() {
        val size = layerPixelSize(
            widthFraction = 0.5,
            heightFraction = 0.25,
            sourceWidth = 1080,
            sourceHeight = 1920,
            renderSize = TimelineRenderSize(1080, 1920)
        )

        // 0.25 of the frame height, not 540 · 1920/1080.
        assertEquals(540, size.width)
        assertEquals(480, size.height)
    }

    @Test
    fun from_readsOptionalHeightFraction() {
        assertEquals(0.3, VideoLayerDescriptor.from(fullMap() + ("heightFraction" to 0.3)).heightFraction)
        assertEquals(null, VideoLayerDescriptor.from(fullMap()).heightFraction)
        assertEquals(
            0.3,
            VideoLayerDescriptor.from(fullMap() + ("heightFraction" to 0.3)).toMap()["heightFraction"]
        )
    }

    @Test
    fun compositorSettings_liveFreeResizeScalesAxesIndependently() {
        val baked = layer().copy(sourceWidth = 1080, sourceHeight = 1920)
        val settings = VideoLayerCompositorSettings(
            renderSize = TimelineRenderSize(1080, 1920),
            layersBySequence = mapOf(0 to PlacedVideoLayer(baked, 1_500L..5_500L))
        )

        // Baked: 540 x 960 px (aspect kept). Live: 0.5 wide, 0.25 tall = 540 x 480.
        settings.updatePlacement(baked.copy(heightFraction = 0.25))

        assertEquals(1f, settings.placementFor(0)?.scaleX)
        assertEquals(0.5f, settings.placementFor(0)?.scaleY)
    }

    @Test
    fun from_readsVolumeAndOnlyMapsItWhenNotDefault() {
        assertEquals(0.5, VideoLayerDescriptor.from(fullMap() + ("volume" to 0.5)).volume)
        assertEquals(1.0, VideoLayerDescriptor.from(fullMap()).volume)
        assertEquals(false, VideoLayerDescriptor.from(fullMap()).toMap().containsKey("volume"))
        assertEquals(0.5, VideoLayerDescriptor.from(fullMap() + ("volume" to 0.5)).toMap()["volume"])
    }

    private fun audibleSequence(volume: Double, hasAudio: Boolean) = videoLayerSequence(
        PlacedVideoLayer(
            layer().copy(sourceDurationMs = 6_000L, volume = volume, sourceHasAudio = hasAudio),
            1_500L..5_500L
        ),
        TimelineRenderSize(1080, 1920),
        10_000L
    )

    @Test
    fun layerSequence_withVolumeAndSourceAudio_carriesTheLayerAudio() {
        val sequence = audibleSequence(volume = 0.8, hasAudio = true)
        val items = sequence.editedMediaItems

        assertEquals(setOf(C.TRACK_TYPE_VIDEO, C.TRACK_TYPE_AUDIO), sequence.trackTypes)
        // Only the layer clip keeps its audio; the invisible fillers stay silent.
        assertEquals(listOf(true, false, true), items.map { it.removeAudio })
    }

    @Test
    fun layerSequence_mutedOrSilentSource_staysVideoOnly() {
        assertEquals(setOf(C.TRACK_TYPE_VIDEO), audibleSequence(volume = 0.0, hasAudio = true).trackTypes)
        assertEquals(setOf(C.TRACK_TYPE_VIDEO), audibleSequence(volume = 1.0, hasAudio = false).trackTypes)
        assertEquals(
            listOf(true, true, true),
            audibleSequence(volume = 0.0, hasAudio = true).editedMediaItems.map { it.removeAudio }
        )
    }

    @Test
    fun timelineClip_readsVolumeWithFullVolumeDefault() {
        assertEquals(
            0.3f,
            TimelineClip.from(mapOf("path" to "/a.mp4", "type" to "video", "volume" to 0.3)).volume
        )
        assertEquals(1.0f, TimelineClip.from(mapOf("path" to "/a.mp4", "type" to "video")).volume)
    }
}
