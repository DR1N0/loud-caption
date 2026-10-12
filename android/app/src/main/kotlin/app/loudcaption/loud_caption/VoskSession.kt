package app.loudcaption.loud_caption

import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService

/**
 * Owns one Activity-visible Vosk capture session and forwards unmodified Vosk payloads to Flutter.
 *
 * Vosk callbacks are delivered on the main thread in version 0.3.75. The session ID gate is checked
 * there immediately before an event is sent so callbacks queued by a previous session are ignored.
 */
class VoskSession(
    private val activity: FlutterActivity,
    private val worker: ExecutorService = Executors.newSingleThreadExecutor(),
) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val installer = ModelInstaller(File(activity.filesDir, "vosk-models"))
    private val gate = SessionGate()
    private val captureStartLock = Any()

    @Volatile
    private var visible = false

    @Volatile
    private var destroyed = false

    // These are accessed exclusively by [worker].
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var service: SpeechService? = null

    // These are accessed exclusively by the main thread.
    private var eventSink: EventChannel.EventSink? = null
    private var queuedSessionId: Int? = null
    private val pendingEvents = ArrayDeque<Map<String, Any>>(MAX_PENDING_EVENTS)

    fun markVisible() {
        visible = true
    }

    fun start(language: String?, result: MethodChannel.Result) {
        if (destroyed) {
            finishStartFailure(result, "session_destroyed", "Speech session is no longer available")
            return
        }
        if (activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            finishStartFailure(result, "permission_denied", "Microphone permission is required")
            return
        }
        val requestedLanguage = language ?: run {
            finishStartFailure(result, "unsupported_language", "Unsupported language: $language")
            return
        }
        if (requestedLanguage !in SUPPORTED_LANGUAGES) {
            finishStartFailure(result, "unsupported_language", "Unsupported language: $requestedLanguage")
            return
        }

        val sessionId = gate.begin()
        runOnMain {
            clearPendingEvents()
            queuedSessionId = sessionId
        }
        submitWorker {
            releaseResources()
            if (!visible || !gate.accepts(sessionId)) {
                finishStartFailure(result, "cancelled", "Speech session was cancelled before capture started")
                return@submitWorker
            }

            try {
                val zipName = zipNameFor(requestedLanguage)
                val assetKey = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/models/$zipName")
                val modelDir = installer.ensureInstalled(requestedLanguage) { activity.assets.open(assetKey) }

                // Model extraction may take long enough for the Activity to become invisible.
                if (!visible || !gate.accepts(sessionId)) {
                    finishStartFailure(result, "cancelled", "Speech session was cancelled while loading the model")
                    return@submitWorker
                }

                // Assign every native resource immediately so the catch path owns and closes it
                // even when a later Vosk constructor fails.
                model = Model(modelDir.absolutePath)
                recognizer = Recognizer(requireNotNull(model), SAMPLE_RATE)
                service = SpeechService(requireNotNull(recognizer), SAMPLE_RATE)
                val loadedService = requireNotNull(service)

                synchronized(captureStartLock) {
                    // onStop sets visible=false before acquiring this lock. It therefore either
                    // prevents capture from starting or waits until this brief call completes.
                    check(visible && gate.accepts(sessionId)) {
                        "Speech session was cancelled before microphone capture started"
                    }
                    check(loadedService.startListening(listenerFor(sessionId))) {
                        "Vosk could not start microphone capture"
                    }
                }
                runOnMain {
                    if (gate.accepts(sessionId)) {
                        result.success(sessionId)
                    } else {
                        result.error("cancelled", "Speech session was cancelled before capture started", null)
                    }
                }
            } catch (error: Exception) {
                failStart(result, sessionId, "start_failed", error)
            } catch (error: LinkageError) {
                failStart(result, sessionId, "native_link_failed", error)
            }
        }
    }

    fun stop(result: MethodChannel.Result) {
        if (destroyed) {
            runOnMain { result.success(null) }
            return
        }
        gate.invalidate()
        blockCaptureStart()
        runOnMain { clearPendingEvents() }
        submitWorker {
            releaseResources()
            runOnMain { result.success(null) }
        }
    }

    /** Reports logical session health without changing native capture state. */
    fun isSessionActive(id: Int, result: MethodChannel.Result) {
        if (destroyed) {
            runOnMain { result.success(false) }
            return
        }
        try {
            worker.execute {
                val active = !destroyed && visible && gate.accepts(id) &&
                    model != null && recognizer != null && service != null
                runOnMain {
                    result.success(active && !destroyed && visible && gate.accepts(id))
                }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            runOnMain { result.success(false) }
        }
    }

    /** Called when the Activity is no longer visible; this must never create a user-visible error. */
    fun cancelOnBackground() {
        visible = false
        gate.invalidate()
        blockCaptureStart()
        runOnMain { clearPendingEvents() }
        submitWorker { releaseResources() }
    }

    /** Releases the capture session, then prevents any further work from being accepted. */
    fun destroy() {
        if (destroyed) return
        destroyed = true
        visible = false
        gate.invalidate()
        blockCaptureStart()
        runOnMain { clearPendingEvents() }
        // This final task is deliberately submitted after marking the session destroyed. It runs
        // after any in-flight extraction or cleanup, releases capture, then stops the executor.
        worker.execute {
            releaseResources()
            worker.shutdown()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        runOnMain {
            eventSink = events
            val queuedId = queuedSessionId
            if (queuedId == null) {
                clearPendingEvents()
                return@runOnMain
            }
            // A terminal error is deliberately queued before its ID is invalidated so an event
            // subscriber that attaches immediately afterward still observes the error.
            if (!gate.accepts(queuedId) && pendingEvents.any { it["kind"] != "error" }) {
                clearPendingEvents()
                return@runOnMain
            }
            while (pendingEvents.isNotEmpty()) {
                events.success(pendingEvents.removeFirst())
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        runOnMain {
            eventSink = null
        }
    }

    private fun listenerFor(sessionId: Int): RecognitionListener = object : RecognitionListener {
        override fun onPartialResult(hypothesis: String) = postEvent(sessionId, "partial", hypothesis)

        override fun onResult(hypothesis: String) = postEvent(sessionId, "final", hypothesis)

        override fun onFinalResult(hypothesis: String) = postEvent(sessionId, "final", hypothesis)

        override fun onError(exception: Exception) = terminateWithError(
            sessionId,
            exception.message ?: exception.toString(),
        )

        override fun onTimeout() = terminateWithError(sessionId, TIMEOUT_ERROR)
    }

    /**
     * Delivers one terminal error for the active session, then rejects any callback that was
     * already queued. This ordering is required so the error itself is not treated as stale.
     */
    private fun terminateWithError(sessionId: Int, raw: String) {
        runOnMain {
            if (!gate.accepts(sessionId)) return@runOnMain
            emitOrQueue(sessionId, "error", raw)
            gate.invalidate()
            clearPendingEventsAfterCurrentError(sessionId)
            submitWorker { releaseResources() }
        }
    }

    private fun postEvent(sessionId: Int, kind: String, raw: String) {
        runOnMain {
            if (gate.accepts(sessionId)) {
                emitOrQueue(sessionId, kind, raw)
            }
        }
    }

    private fun emitOrQueue(sessionId: Int, kind: String, raw: String) {
        val event = mapOf("raw" to raw, "kind" to kind, "sessionId" to sessionId)
        if (eventSink != null) {
            eventSink!!.success(event)
            return
        }
        if (queuedSessionId != sessionId) {
            pendingEvents.clear()
            queuedSessionId = sessionId
        }
        if (pendingEvents.size == MAX_PENDING_EVENTS) {
            pendingEvents.removeFirst()
        }
        pendingEvents.addLast(event)
    }

    private fun clearPendingEventsAfterCurrentError(sessionId: Int) {
        // Keep the error already sent or queued, but ensure no earlier partials are replayed later.
        if (eventSink == null && queuedSessionId == sessionId) {
            val error = pendingEvents.lastOrNull()
            pendingEvents.clear()
            if (error != null) pendingEvents.addLast(error)
        }
    }

    private fun clearPendingEvents() {
        pendingEvents.clear()
        queuedSessionId = null
    }

    private fun clearPendingEventsFor(sessionId: Int) {
        if (queuedSessionId == sessionId) {
            clearPendingEvents()
        }
    }

    /**
     * Must run on [worker]. In Vosk 0.3.75 cancel() interrupts and joins the recognizer thread;
     * only then may shutdown(), recognizer.close(), and model.close() run in that order.
     */
    private fun releaseResources() {
        val currentService = service
        val currentRecognizer = recognizer
        val currentModel = model
        service = null
        recognizer = null
        model = null

        releaseSafely { currentService?.cancel() }
        releaseSafely { currentService?.shutdown() }
        releaseSafely { currentRecognizer?.close() }
        releaseSafely { currentModel?.close() }
    }

    private inline fun releaseSafely(release: () -> Unit) {
        try {
            release()
        } catch (_: Exception) {
            // Continue releasing the remaining resources.
        } catch (_: LinkageError) {
            // JNI initialization may have failed before the resource could be closed.
        }
    }

    private fun failStart(result: MethodChannel.Result, sessionId: Int, code: String, error: Throwable) {
        releaseResources()
        if (gate.accepts(sessionId)) {
            gate.invalidate()
        }
        runOnMain { clearPendingEventsFor(sessionId) }
        finishStartFailure(result, code, error.message ?: error.toString())
    }

    private fun finishStartFailure(result: MethodChannel.Result, code: String, message: String) {
        runOnMain { result.error(code, message, null) }
    }

    /** Waits only for an in-progress startListening call, never for model extraction. */
    private fun blockCaptureStart() {
        synchronized(captureStartLock) { }
    }

    private fun submitWorker(task: () -> Unit) {
        if (!destroyed) {
            worker.execute(task)
        }
    }

    private fun runOnMain(task: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            task()
        } else {
            mainHandler.post(task)
        }
    }

    private fun zipNameFor(language: String): String = when (language) {
        "en" -> "vosk-model-small-en-us-0.15.zip"
        "zh" -> "vosk-model-small-cn-0.22.zip"
        else -> throw IllegalArgumentException("Unsupported language: $language")
    }

    private companion object {
        val SUPPORTED_LANGUAGES = setOf("en", "zh")
        const val SAMPLE_RATE = 16_000f
        const val MAX_PENDING_EVENTS = 16
        const val TIMEOUT_ERROR = "Recognition timed out"
    }
}
