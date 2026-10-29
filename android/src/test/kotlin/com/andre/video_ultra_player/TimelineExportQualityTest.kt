package com.andre.video_ultra_player

import androidx.media3.effect.FrameDropEffect
import androidx.media3.transformer.Composition
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

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

    @Test
    fun config_parsesCustomSizeAndFrameRate() {
        val config = TimelineCompositionConfig.from(
            mapOf(
                "aspectRatio" to "custom",
                "customWidth" to 1080,
                "customHeight" to 1350,
                "frameRate" to 24
            )
        )

        assertEquals(OutputAspectRatio.CUSTOM, config.aspectRatio)
        assertEquals(1080, config.customWidth)
        assertEquals(1350, config.customHeight)
        assertEquals(24, config.frameRate)
    }

    @Test
    fun config_withoutFrameRateKeepsPlatformDefault() {
        val config = TimelineCompositionConfig.from(mapOf("aspectRatio" to "ratio9x16"))

        assertNull(config.frameRate)
        assertNull(config.customWidth)
    }

    @Test
    fun outputSizeFor_usesCustomCanvas() {
        val config = TimelineCompositionConfig.from(
            mapOf("aspectRatio" to "custom", "customWidth" to 1080, "customHeight" to 1350)
        )

        assertEquals(TimelineRenderSize(1080, 1350), outputSizeFor(config, videoClip(0)))
    }

    @Test
    fun outputSizeFor_customWithoutSizeFallsBackToOriginal() {
        val config = TimelineCompositionConfig.from(mapOf("aspectRatio" to "custom"))
        val original = TimelineCompositionConfig(aspectRatio = OutputAspectRatio.ORIGINAL)
        val clip = videoClip(0)

        assertEquals(outputSizeFor(original, clip), outputSizeFor(config, clip))
    }

    @Test
    fun exportFrameRateEffects_emptyWithoutFrameRate() {
        assertTrue(exportFrameRateEffects(null).isEmpty())
    }

    @Test
    fun exportFrameRateEffects_dropsFramesToTarget() {
        val effects = exportFrameRateEffects(24)

        assertEquals(1, effects.size)
        assertIs<FrameDropEffect>(effects.single())
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
