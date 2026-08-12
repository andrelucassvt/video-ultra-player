package com.andre.video_ultra_player

import androidx.media3.transformer.ExportException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class TimelineExportErrorDetailsTest {

    @Test
    fun exportErrorDetails_includesErrorCodeNameForExportException() {
        val error = ExportException.createForCodec(
            RuntimeException("underlying failure"),
            ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
            ExportException.CodecInfo("video/avc", true, false, "OMX.TestEncoder")
        )

        val details = exportErrorDetails(error)

        assertTrue(details.startsWith("errorCodeName="))
        assertTrue(details.contains("ERROR_CODE_ENCODER_INIT_FAILED"))
        assertTrue(details.contains("RuntimeException: underlying failure"))
    }

    @Test
    fun exportErrorDetails_includesMessageAndCauseChainForPlainErrors() {
        val root = IllegalStateException("root cause")
        val middle = RuntimeException("middle failure", root)
        val error = Exception("top failure", middle)

        val details = exportErrorDetails(error)

        assertFalse(details.contains("errorCodeName"))
        assertTrue(details.contains("top failure"))
        assertTrue(details.contains("RuntimeException: middle failure"))
        assertTrue(details.contains("IllegalStateException: root cause"))
    }

    @Test
    fun exportErrorDetails_fallsBackToTypeNameWhenMessageIsNull() {
        val details = exportErrorDetails(IllegalStateException())

        assertEquals("IllegalStateException", details)
    }

    @Test
    fun exportErrorDetails_capsCauseChainAtFiveLevels() {
        var cause: Throwable? = null
        for (i in 10 downTo 1) {
            cause = RuntimeException("causeLevel$i", cause)
        }

        val details = exportErrorDetails(cause!!)

        // The top error plus five causes — deeper levels are dropped.
        assertEquals(6, details.split("causeLevel").size - 1)
        assertTrue(details.contains("causeLevel1"))
        assertTrue(details.contains("causeLevel6"))
        assertFalse(details.contains("causeLevel7"))
    }
}
