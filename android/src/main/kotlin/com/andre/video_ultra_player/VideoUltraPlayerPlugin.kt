package com.andre.video_ultra_player

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/** VideoUltraPlayerPlugin */
class VideoUltraPlayerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var applicationContext: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private val controllers = mutableMapOf<Long, TimelineCompositionController>()
    private val activeExporters = mutableSetOf<TimelineCompositionExporter>()

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
        activeExporters.forEach { it.cancel() }
        activeExporters.clear()
        controllers.values.forEach { it.dispose() }
        controllers.clear()
        methodChannel = null
        eventChannel = null
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
        if (clips == null) {
            result.error("invalid_arguments", "Expected clips list.", null)
            return
        }

        try {
            val controller = TimelineCompositionController(context, registry)
            val textureId = controller.load(clips)
            controllers[textureId] = controller
            result.success(textureId)
        } catch (error: Throwable) {
            result.error(
                "load_failed",
                "Unable to build native timeline composition.",
                error.message
            )
        }
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
        if (clips == null) {
            result.error("invalid_arguments", "Expected clips list.", null)
            return
        }

        val exporter = TimelineCompositionExporter(context)
        activeExporters.add(exporter)
        try {
            exporter.export(
                rawClips = clips,
                outputPath = outputPath,
                callback = object : TimelineExportCallback {
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
            result.error(
                "export_failed",
                "Unable to export native timeline composition.",
                error.message
            )
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
