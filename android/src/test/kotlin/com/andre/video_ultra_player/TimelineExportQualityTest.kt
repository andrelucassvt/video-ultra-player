package com.andre.video_ultra_player

import androidx.media3.transformer.Composition
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TimelineExportQualityTest {
    @Test
    fun config_parsesMediaCodecToneMappingAndSourceQuality() {
        val config = TimelineCompositionConfig.from(
            mapOf(
                "aspectRatio" to "original",
                "baseWidth" to 1080,
                "hdrMode" to "toneMapToSdrUsingMediaCodec",
                "preserveSourceQuality" to true
            )
        )

        assertEquals(
            Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC,
            config.media3HdrMode
        )
        assertEquals(true, config.preserveSourceQuality)
    }

    @Test
    fun preferredVideoBitrate_usesHighestSourceBitrateWhenEnabled() {
        val clips = listOf(videoClip(sourceBitrate = 8_000_000), videoClip(sourceBitrate = 15_000_000))

        val bitrate = preferredVideoBitrate(
            TimelineCompositionConfig(preserveSourceQuality = true),
            clips
        )

        assertEquals(15_000_000, bitrate)
    }

    @Test
    fun preferredVideoBitrate_leavesEncoderDefaultWhenDisabled() {
        val bitrate = preferredVideoBitrate(
            TimelineCompositionConfig(preserveSourceQuality = false),
            listOf(videoClip(sourceBitrate = 15_000_000))
        )

        assertNull(bitrate)
    }

    private fun videoClip(sourceBitrate: Int) = TimelineClip(
        path = "/tmp/video.mp4",
        type = TimelineMediaType.VIDEO,
        durationMs = null,
        alignmentX = 0.0,
        alignmentY = 0.0,
        scale = 1.0,
        sourceBitrate = sourceBitrate
    )
}
