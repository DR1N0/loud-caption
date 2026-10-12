package app.loudcaption.loud_caption

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var voskSession: VoskSession

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        voskSession = VoskSession(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> voskSession.start(call.argument<String>("language"), result)
                "stop" -> voskSession.stop(result)
                "isSessionActive" -> {
                    val id = sessionIdArgument(call.argument<Any?>("sessionId"))
                    if (id == null) {
                        result.error("invalid_session_id", "sessionId must be an integer", null)
                    } else {
                        voskSession.isSessionActive(id, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(voskSession)
    }

    override fun onStart() {
        super.onStart()
        if (::voskSession.isInitialized) {
            voskSession.markVisible()
        }
    }

    override fun onStop() {
        if (::voskSession.isInitialized) {
            voskSession.cancelOnBackground()
        }
        super.onStop()
    }

    override fun onDestroy() {
        if (::voskSession.isInitialized) {
            voskSession.destroy()
        }
        super.onDestroy()
    }

    private companion object {
        const val METHOD_CHANNEL = "app.loudcaption/speech/methods"
        const val EVENT_CHANNEL = "app.loudcaption/speech/events"
    }
}
