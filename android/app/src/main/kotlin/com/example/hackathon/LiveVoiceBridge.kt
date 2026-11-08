package com.example.hackathon

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/** Low-latency Android system TTS for live conversation turns. */
class LiveVoiceBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "sentinel/live_voice"
        const val EVENT_CHANNEL = "sentinel/live_voice/events"
        private const val TAG = "LiveVoice"
    }

    private val main = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var sink: EventChannel.EventSink? = null
    private var tts: TextToSpeech? = null
    private var initState: Int? = null
    private var initFailure: String? = null
    private val readyWaiters = mutableListOf<(Result<TextToSpeech>) -> Unit>()
    private val pending = ConcurrentHashMap<String, MethodChannel.Result>()
    private val watchdogs = ConcurrentHashMap<String, Runnable>()
    private val startedTokens = ConcurrentHashMap.newKeySet<String>()
    private var selectedLocale = Locale.UK
    private var originalCommunicationDevice: AudioDeviceInfo? = null
    private var changedCommunicationDevice = false
    private var conversationMode = false
    private var disposed = false
    private var initializationTicket = 0
    @Volatile private var generation = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "prepare" || call.method == "speak") disposed = false
        when (call.method) {
            "prepare" -> ensureReady { ready ->
                ready.fold(onSuccess = { engine ->
                    val locale = chooseLocale(engine, call.argument<String>("locale"))
                    if (locale == null) result.error("voice_unavailable", "No installed English local speech voice is available.", null)
                    else {
                        selectedLocale = locale
                        result.success(mapOf("locale" to locale.toLanguageTag(), "voiceName" to engine.voice?.name))
                    }
                }, onFailure = { error -> result.error("tts_init", error.message ?: "Android speech engine failed to initialize.", null) })
            }
            "speak" -> speak(call, result)
            "stop" -> { stop("Speech stopped."); result.success(null) }
            "dispose" -> { stop("Speech service disposed."); release(); result.success(null) }
            "setConversationMode" -> {
                conversationMode = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            }
            "setSpeechRate" -> {
                val rate = call.argument<Number>("rate")?.toFloat() ?: 1f
                ensureReady { ready -> ready.fold({ it.setSpeechRate((rate * 2f).coerceIn(.5f, 4f)); result.success(null) }, { result.error("tts_init", it.message, null) }) }
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureReady(done: (Result<TextToSpeech>) -> Unit) {
        if (disposed) { done(Result.failure(IllegalStateException("Speech service was disposed."))); return }
        tts?.let { engine ->
            when (initState) {
                TextToSpeech.SUCCESS -> done(Result.success(engine))
                TextToSpeech.ERROR -> done(Result.failure(IllegalStateException(initFailure ?: "Android speech engine failed.")))
                else -> readyWaiters.add(done)
            }
            return
        }
        readyWaiters.add(done)
        val ticket = ++initializationTicket
        try {
            tts = TextToSpeech(context.applicationContext) { status ->
                main.post {
                    if (ticket != initializationTicket || disposed) return@post
                    initState = status
                    val engine = tts
                    if (status == TextToSpeech.SUCCESS && engine != null) {
                        engine.setAudioAttributes(AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                        engine.setOnUtteranceProgressListener(listener)
                    } else initFailure = "Android speech engine initialization failed (code $status)."
                    val callbacks = readyWaiters.toList(); readyWaiters.clear()
                    callbacks.forEach { waiter ->
                        if (status == TextToSpeech.SUCCESS && engine != null) waiter(Result.success(engine))
                        else waiter(Result.failure(IllegalStateException(initFailure)))
                    }
                }
            }
        } catch (error: Exception) {
            initState = TextToSpeech.ERROR
            initFailure = error.message ?: "Could not create Android speech engine."
            val callbacks = readyWaiters.toList(); readyWaiters.clear()
            callbacks.forEach { it(Result.failure(IllegalStateException(initFailure))) }
        }
        main.postDelayed({
            if (ticket == initializationTicket && initState == null && !disposed) {
                initState = TextToSpeech.ERROR
                initFailure = "Android speech engine did not initialize within 5 seconds."
                tts?.shutdown(); tts = null
                val callbacks = readyWaiters.toList(); readyWaiters.clear()
                callbacks.forEach { it(Result.failure(IllegalStateException(initFailure))) }
            }
        }, 5_000)
    }

    private fun chooseLocale(engine: TextToSpeech, requested: String?): Locale? {
        val requestedLocale = requested?.let(Locale::forLanguageTag)?.takeIf { it.language == "en" }
        val candidates = listOfNotNull(requestedLocale, Locale.UK, Locale.US).distinct()
        val voices = engine.voices ?: emptySet()
        return candidates.firstOrNull { locale ->
            val voice = voices.firstOrNull { it.locale.language == locale.language && it.locale.country == locale.country && !it.isNetworkConnectionRequired }
            if (voice != null) { engine.voice = voice; true }
            else engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE && engine.voices?.any {
                it.locale.language == locale.language && !it.isNetworkConnectionRequired
            } == true && engine.setLanguage(locale) >= TextToSpeech.LANG_AVAILABLE
        }
    }

    private fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim().orEmpty()
        if (text.isEmpty()) { result.success(null); return }
        val token = call.argument<String>("token") ?: "live-${System.nanoTime()}"
        val localeTag = call.argument<String>("locale")
        val rate = call.argument<Number>("rate")?.toFloat() ?: 0.5f
        val requestGeneration = generation
        ensureReady { ready ->
            if (requestGeneration != generation) { result.error("cancelled", "Speech request was cancelled.", null); return@ensureReady }
            ready.fold(onSuccess = { engine ->
                val locale = chooseLocale(engine, localeTag)
                if (locale == null) { result.error("voice_unavailable", "No installed English local speech voice is available.", null); return@fold }
                selectedLocale = locale
                routeForSpeech()
                engine.setSpeechRate((rate * 2f).coerceIn(.5f, 4f))
                val timeout = (text.length * 250L).coerceIn(15_000L, 90_000L)
                pending[token] = result
                val startupWatchdog = Runnable {
                    if (!startedTokens.contains(token)) {
                        engine.stop()
                        finish(token, false, "Android speech playback did not start within 5 seconds.")
                    }
                }
                watchdogs[token] = startupWatchdog
                main.postDelayed(startupWatchdog, 5_000)
                val playbackWatchdog = Runnable { finish(token, false, "Speech playback timed out.") }
                watchdogs["done:$token"] = playbackWatchdog
                main.postDelayed(playbackWatchdog, timeout)
                val status = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, token)
                if (status != TextToSpeech.SUCCESS) finish(token, false, "Android speech engine rejected the utterance (code $status).")
            }, onFailure = { error -> result.error("tts_init", error.message ?: "Android speech engine failed.", null) })
        }
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) {
            android.util.Log.i(TAG, "onStart")
            startedTokens.add(utteranceId)
            watchdogs.remove(utteranceId)?.let(main::removeCallbacks)
            emit("started", utteranceId)
        }
        override fun onDone(utteranceId: String) { android.util.Log.i(TAG, "onDone"); finish(utteranceId, true, null) }
        @Deprecated("Deprecated in Java") override fun onError(utteranceId: String) { finish(utteranceId, false, "Android speech playback failed.") }
        override fun onError(utteranceId: String, errorCode: Int) { finish(utteranceId, false, "Android speech playback failed (code $errorCode).") }
        override fun onStop(utteranceId: String, interrupted: Boolean) { finish(utteranceId, false, "Speech playback was interrupted.") }
    }

    private fun finish(token: String, success: Boolean, message: String?) {
        val result = pending.remove(token) ?: return
        main.post {
            watchdogs.remove(token)?.let(main::removeCallbacks)
            watchdogs.remove("done:$token")?.let(main::removeCallbacks)
            startedTokens.remove(token)
            emit(if (success) "completed" else "error", token, message)
            if (success) result.success(null) else result.error("playback_failed", message ?: "Speech playback failed.", null)
            if (pending.isEmpty()) restoreCommunicationRoute()
        }
    }

    private fun emit(type: String, token: String, message: String? = null) {
        main.post { sink?.success(mapOf("type" to type, "token" to token).let { if (message == null) it else it + ("message" to message) }) }
    }

    private fun routeForSpeech() {
        if (Build.VERSION.SDK_INT < 31) return
        val devices = audioManager.availableCommunicationDevices
        val current = audioManager.communicationDevice
        val headsetTypes = setOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET)
        if (current?.type in headsetTypes) return
        val headset = devices.firstOrNull { it.type in headsetTypes }
        if (headset != null) {
            if (!changedCommunicationDevice) originalCommunicationDevice = current
            changedCommunicationDevice = audioManager.setCommunicationDevice(headset)
            return
        }
        val speaker = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER } ?: return
        if (!changedCommunicationDevice) originalCommunicationDevice = current
        changedCommunicationDevice = audioManager.setCommunicationDevice(speaker)
    }

    private fun restoreCommunicationRoute() {
        if (Build.VERSION.SDK_INT >= 31 && changedCommunicationDevice) {
            val previous = originalCommunicationDevice
            if (previous != null && audioManager.availableCommunicationDevices.any { it.id == previous.id }) audioManager.setCommunicationDevice(previous)
            else audioManager.clearCommunicationDevice()
        }
        changedCommunicationDevice = false
        originalCommunicationDevice = null
    }

    private fun stop(message: String) {
        generation++
        tts?.stop()
        pending.keys.toList().forEach { finish(it, false, message) }
        restoreCommunicationRoute()
    }

    private fun release() {
        initializationTicket++
        disposed = true
        tts?.shutdown(); tts = null; initState = null
        val callbacks = readyWaiters.toList(); readyWaiters.clear()
        callbacks.forEach { it(Result.failure(IllegalStateException("Speech service was disposed."))) }
    }

    fun dispose() {
        stop("Speech service disposed.")
        release()
    }
}
