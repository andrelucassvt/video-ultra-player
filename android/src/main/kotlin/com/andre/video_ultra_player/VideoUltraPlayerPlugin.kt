package com.andre.video_ultra_player

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

/** VideoUltraPlayerPlugin */
class VideoUltraPlayerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var exportEventChannel: EventChannel? = null
    private var applicationContext: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private val controllers = mutableMapOf<Long, TimelineCompositionController>()
    private val activeExporters = mutableSetOf<TimelineCompositionExporter>()
    private val exportProgressHandler = ExportProgressStreamHandler()

    // Background executor and main-thread handler used for thumbnail generation.
    // Lazy so plain JVM unit tests can construct the plugin without a mocked Looper.
    private val thumbnailExecutor = Executors.newCachedThreadPool()
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        textureRegistry = flutterPluginBinding.textureRegistry
        methodChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "video_ultra_player/timeline_player"
        ).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "video_ultra_player/timeline_player/events"
        ).also { it.setStreamHandler(this) }
        exportEventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "video_ultra_player/timeline_player/export"
        ).also { it.setStreamHandler(exportProgressHandler) }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "load" -> load(call, result)
            "exportTimeline" -> exportTimeline(call, result)
            "play" -> withController(call, result) { controller ->
                controller.play()
                result.success(null)
            }
            "pause" -> withController(call, result) { controller ->
                controller.pause()
                result.success(null)
            }
            "seekTo" -> withController(call, result) { controller ->
                val positionMs = numberArg(call.arguments, "positionMs")?.toLong()
                if (positionMs == null) {
                    result.error("invalid_arguments", "Expected positionMs.", null)
                    return@withController
                }
                controller.seekTo(positionMs)
                result.success(null)
            }
            "seekToClip" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                if (clipIndex == null) {
                    result.error("invalid_arguments", "Expected clipIndex.", null)
                    return@withController
                }
                controller.seekToClip(clipIndex)
                result.success(null)
            }
            "setVolume" -> withController(call, result) { controller ->
                val volume = numberArg(call.arguments, "volume")?.toDouble()
                if (volume == null) {
                    result.error("invalid_arguments", "Expected volume.", null)
                    return@withController
                }
                controller.setVolume(volume)
                result.success(null)
            }
            "setClipAlignment" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                val x = numberArg(call.arguments, "x")?.toDouble()
                val y = numberArg(call.arguments, "y")?.toDouble()
                if (clipIndex == null || x == null || y == null) {
                    result.error(
                        "invalid_arguments",
                        "Expected clipIndex, x and y.",
                        null
                    )
                    return@withController
                }
                controller.setClipAlignment(clipIndex, x, y)
                result.success(null)
            }
            "setCompositionConfig" -> withController(call, result) { controller ->
                val config = (call.arguments as? Map<*, *>)?.get("config") as? Map<*, *>
                if (config == null) {
                    result.error("invalid_arguments", "Expected config.", null)
                    return@withController
                }
                try {
                    controller.setCompositionConfig(config)
                    result.success(null)
                } catch (error: Throwable) {
                    Log.e("VideoUltraPlayer", "setCompositionConfig failed", error)
                    result.error(
                        "edit_failed",
                        "setCompositionConfig failed: ${error.message ?: error.toString()}",
                        Log.getStackTraceString(error)
                    )
                }
            }
            "trimClip" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                if (clipIndex == null) {
                    result.error("invalid_arguments", "Expected clipIndex.", null)
                    return@withController
                }
                val trimStartMs = numberArg(call.arguments, "trimStartMs")?.toLong()
                val trimEndMs = numberArg(call.arguments, "trimEndMs")?.toLong()
                controller.trimClip(clipIndex, trimStartMs, trimEndMs)
                result.success(null)
            }
            "splitClip" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                val atLocalPositionMs = numberArg(call.arguments, "atLocalPositionMs")?.toLong()
                if (clipIndex == null || atLocalPositionMs == null) {
                    result.error("invalid_arguments", "Expected clipIndex and atLocalPositionMs.", null)
                    return@withController
                }
                controller.splitClip(clipIndex, atLocalPositionMs)
                result.success(null)
            }
            "insertClip" -> withController(call, result) { controller ->
                val args = call.arguments as? Map<*, *>
                val atIndex = numberArg(call.arguments, "atIndex")?.toInt()
                val clipDict = args?.get("clip") as? Map<*, *>
                if (atIndex == null || clipDict == null) {
                    result.error("invalid_arguments", "Expected atIndex and clip.", null)
                    return@withController
                }
                try {
                    controller.insertClip(atIndex, clipDict)
                    result.success(null)
                } catch (e: Throwable) {
                    result.error("edit_failed", "insertClip failed: ${e.message}", null)
                }
            }
            "removeClip" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                if (clipIndex == null) {
                    result.error("invalid_arguments", "Expected clipIndex.", null)
                    return@withController
                }
                controller.removeClip(clipIndex)
                result.success(null)
            }
            "moveClip" -> withController(call, result) { controller ->
                val fromIndex = numberArg(call.arguments, "fromIndex")?.toInt()
                val toIndex = numberArg(call.arguments, "toIndex")?.toInt()
                if (fromIndex == null || toIndex == null) {
                    result.error("invalid_arguments", "Expected fromIndex and toIndex.", null)
                    return@withController
                }
                controller.moveClip(fromIndex, toIndex)
                result.success(null)
            }
            "replaceClip" -> withController(call, result) { controller ->
                val args = call.arguments as? Map<*, *>
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                val clipDict = args?.get("clip") as? Map<*, *>
                if (clipIndex == null || clipDict == null) {
                    result.error("invalid_arguments", "Expected clipIndex and clip.", null)
                    return@withController
                }
                try {
                    controller.replaceClip(clipIndex, clipDict)
                    result.success(null)
                } catch (e: Throwable) {
                    result.error("edit_failed", "replaceClip failed: ${e.message}", null)
                }
            }
            "setClipSpeed" -> withController(call, result) { controller ->
                val clipIndex = numberArg(call.arguments, "clipIndex")?.toInt()
                val speed = numberArg(call.arguments, "speed")?.toFloat()
                if (clipIndex == null || speed == null) {
                    result.error("invalid_arguments", "Expected clipIndex and speed.", null)
                    return@withController
                }
                controller.setClipSpeed(clipIndex, speed)
                result.success(null)
            }
            "setAudioTrack" -> withController(call, result) { controller ->
                val args = call.arguments as? Map<*, *>
                val track = args?.get("track") as? Map<*, *>
                if (track == null) {
                    result.error("invalid_arguments", "Expected track.", null)
                    return@withController
                }
                try {
                    controller.setAudioTrack(track)
                    result.success(null)
                } catch (error: Throwable) {
                    Log.e("VideoUltraPlayer", "setAudioTrack failed", error)
                    result.error(
                        "edit_failed",
                        "setAudioTrack failed: ${error.message ?: error.toString()}",
                        Log.getStackTraceString(error)
                    )
                }
            }
            "removeAudioTrack" -> withController(call, result) { controller ->
                controller.removeAudioTrack()
                result.success(null)
            }
            "addTextOverlay" -> withController(call, result) { controller ->
                val overlay = (call.arguments as? Map<*, *>)?.get("overlay") as? Map<*, *>
                if (overlay == null) {
                    result.error("invalid_arguments", "Expected overlay.", null)
                    return@withController
                }
                try {
                    controller.addTextOverlay(overlay)
                    result.success(null)
                } catch (error: Throwable) {
                    Log.e("VideoUltraPlayer", "addTextOverlay failed", error)
                    result.error(
                        "edit_failed",
                        "addTextOverlay failed: ${error.message ?: error.toString()}",
                        Log.getStackTraceString(error)
                    )
                }
            }
            "updateTextOverlay" -> withController(call, result) { controller ->
                val overlay = (call.arguments as? Map<*, *>)?.get("overlay") as? Map<*, *>
                if (overlay == null) {
                    result.error("invalid_arguments", "Expected overlay.", null)
                    return@withController
                }
                try {
                    controller.updateTextOverlay(overlay)
                    result.success(null)
                } catch (error: Throwable) {
                    Log.e("VideoUltraPlayer", "updateTextOverlay failed", error)
                    result.error(
                        "edit_failed",
                        "updateTextOverlay failed: ${error.message ?: error.toString()}",
                        Log.getStackTraceString(error)
                    )
                }
            }
            "removeTextOverlay" -> withController(call, result) { controller ->
                val overlayId = (call.arguments as? Map<*, *>)?.get("overlayId") as? String
                if (overlayId == null) {
                    result.error("invalid_arguments", "Expected overlayId.", null)
                    return@withController
                }
                controller.removeTextOverlay(overlayId)
                result.success(null)
            }
            "undo" -> withController(call, result) { controller ->
                controller.undo()
                result.success(null)
            }
            "redo" -> withController(call, result) { controller ->
                controller.redo()
                result.success(null)
            }
            "generateThumbnails" -> generateThumbnails(call, result)
            "exportCurrentTimeline" -> exportCurrentTimeline(call, result)
            "dispose" -> {
                val textureId = textureId(call.arguments)
                if (textureId == null) {
                    result.error("invalid_arguments", "Expected textureId.", null)
                    return
                }
                controllers.remove(textureId)?.dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        exportEventChannel?.setStreamHandler(null)
        activeExporters.forEach { it.cancel() }
        activeExporters.clear()
        controllers.values.forEach { it.dispose() }
        controllers.clear()
        thumbnailExecutor.shutdown()
        methodChannel = null
        eventChannel = null
        exportEventChannel = null
        applicationContext = null
        textureRegistry = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val textureId = textureId(arguments)
        if (textureId == null) {
            events.error("invalid_arguments", "Expected textureId.", null)
            return
        }
        controllers[textureId]?.setEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        val textureId = textureId(arguments) ?: return
        controllers[textureId]?.setEventSink(null)
    }

    private fun load(
        call: MethodCall,
        result: Result
    ) {
        val context = applicationContext
        val registry = textureRegistry
        if (context == null || registry == null) {
            result.error(
                "not_attached",
                "VideoUltraPlayerPlugin is not attached to the Flutter engine.",
                null
            )
            return
        }

        val args = call.arguments as? Map<*, *>
        val clips = args?.get("clips") as? List<*>
        val config = args?.get("config") as? Map<*, *>
        if (clips == null) {
            result.error("invalid_arguments", "Expected clips list.", null)
            return
        }

        // Source metadata extraction is blocking I/O, so `load` resolves it off
        // the main thread and calls back once the player is attached.
        val controller = TimelineCompositionController(context, registry)
        controller.load(
            rawClips = clips,
            rawConfig = config,
            onReady = { textureId ->
                controllers[textureId] = controller
                result.success(textureId)
            },
            onError = { error ->
                controller.dispose()
                result.error(
                    "load_failed",
                    "Unable to build native timeline composition.",
                    error.message
                )
            }
        )
    }

    private fun exportTimeline(
        call: MethodCall,
        result: Result
    ) {
        val context = applicationContext
        if (context == null) {
            result.error(
                "not_attached",
                "VideoUltraPlayerPlugin is not attached to the Flutter engine.",
                null
            )
            return
        }

        val args = call.arguments as? Map<*, *>
        val clips = args?.get("clips") as? List<*>
        val outputPath = args?.get("outputPath") as? String
        val config = args?.get("config") as? Map<*, *>
        if (clips == null) {
            result.error("invalid_arguments", "Expected clips list.", null)
            return
        }

        val exporter = TimelineCompositionExporter(context)
        activeExporters.add(exporter)
        try {
            exporter.export(
                rawClips = clips,
                rawConfig = config,
                outputPath = outputPath,
                callback = object : TimelineExportCallback {
                    override fun onProgress(
                        progress: Double,
                        state: String
                    ) {
                        exportProgressHandler.emit(progress, state)
                    }

                    override fun onCompleted(outputPath: String) {
                        activeExporters.remove(exporter)
                        result.success(outputPath)
                    }

                    override fun onError(error: Throwable) {
                        activeExporters.remove(exporter)
                        result.error(
                            "export_failed",
                            "Unable to export native timeline composition.",
                            error.message
                        )
                    }
                }
            )
        } catch (error: Throwable) {
            activeExporters.remove(exporter)
            exporter.cancel()
            exportProgressHandler.emit(0.0, "failed")
            result.error(
                "export_failed",
                "Unable to export native timeline composition.",
                error.message
            )
        }
    }

    private fun exportCurrentTimeline(call: MethodCall, result: Result) {
        val textureId = textureId(call.arguments)
        if (textureId == null) {
            result.error("invalid_arguments", "Expected textureId.", null)
            return
        }
        val controller = controllers[textureId]
        if (controller == null) {
            result.error("not_found", "No native timeline player exists for textureId $textureId.", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val outputPath = args?.get("outputPath") as? String

        // exporterRef allows the callback to remove itself from activeExporters
        // even though the exporter is created inside startExportCurrentTimeline.
        var exporterRef: TimelineCompositionExporter? = null
        val exporter = controller.startExportCurrentTimeline(
            outputPath = outputPath,
            callback = object : TimelineExportCallback {
                override fun onProgress(progress: Double, state: String) {
                    exportProgressHandler.emit(progress, state)
                }

                override fun onCompleted(outputPath: String) {
                    exporterRef?.let { activeExporters.remove(it) }
                    result.success(outputPath)
                }

                override fun onError(error: Throwable) {
                    exporterRef?.let { activeExporters.remove(it) }
                    result.error("export_failed", "Unable to export current timeline.", error.message)
                }
            }
        )
        exporterRef = exporter
        activeExporters.add(exporter)
    }

    private fun generateThumbnails(call: MethodCall, result: Result) {
        val context = applicationContext
        if (context == null) {
            result.error(
                "not_attached",
                "VideoUltraPlayerPlugin is not attached to the Flutter engine.",
                null
            )
            return
        }

        val args = call.arguments as? Map<*, *>
        val videoPath = args?.get("videoPath") as? String
        if (videoPath == null) {
            result.error("invalid_arguments", "generateThumbnails requires videoPath.", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val rawTimestamps = args?.get("timestampsMs") as? List<*>
        val timestampsMs = rawTimestamps?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
        val width = (args?.get("width") as? Number)?.toInt() ?: 120

        thumbnailExecutor.execute {
            val paths = ThumbnailGenerator(context).generate(videoPath, timestampsMs, width)
            mainHandler.post { result.success(paths) }
        }
    }

    private fun withController(
        call: MethodCall,
        result: Result,
        block: (TimelineCompositionController) -> Unit
    ) {
        val textureId = textureId(call.arguments)
        if (textureId == null) {
            result.error("invalid_arguments", "Expected textureId.", null)
            return
        }

        val controller = controllers[textureId]
        if (controller == null) {
            result.error(
                "not_found",
                "No native timeline player exists for textureId $textureId.",
                null
            )
            return
        }

        block(controller)
    }

    private fun textureId(arguments: Any?): Long? {
        return numberArg(arguments, "textureId")?.toLong()
    }

    private fun numberArg(arguments: Any?, key: String): Number? {
        return (arguments as? Map<*, *>)?.get(key) as? Number
    }
}

private class ExportProgressStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink
    ) {
        eventSink = events
        events.success(mapOf("progress" to 0.0, "state" to "idle"))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun emit(
        progress: Double,
        state: String
    ) {
        eventSink?.success(
            mapOf(
                "progress" to progress.coerceIn(0.0, 1.0),
                "state" to state
            )
        )
    }
}
