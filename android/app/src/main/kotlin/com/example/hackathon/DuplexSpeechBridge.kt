package com.example.hackathon

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioManager
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.SpeechRecognizer.ERROR_AUDIO
import android.speech.SpeechRecognizer.ERROR_CLIENT
import android.speech.SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS
import android.speech.SpeechRecognizer.ERROR_NETWORK
import android.speech.SpeechRecognizer.ERROR_NETWORK_TIMEOUT
import android.speech.SpeechRecognizer.ERROR_NO_MATCH
import android.speech.SpeechRecognizer.ERROR_RECOGNIZER_BUSY
import android.speech.SpeechRecognizer.ERROR_SERVER
import android.speech.SpeechRecognizer.ERROR_SPEECH_TIMEOUT
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/** Streams echo-cancelled microphone PCM into Android's on-device/system recognizer. */
class DuplexSpeechBridge(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "sentinel/duplex_speech"
        const val EVENT_CHANNEL = "sentinel/duplex_speech/events"
        private const val SAMPLE_RATE = 16_000
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var recorder: AudioRecord? = null
    private var aec: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var pipeRead: ParcelFileDescriptor? = null
    private var pipeWrite: ParcelFileDescriptor? = null
    private var captureThread: Thread? = null
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var previousAudioMode: Int? = null
    private val running = AtomicBoolean(false)
    @Volatile private var generation = 0
    private val speechGate = SpeechActivityGate(SAMPLE_RATE)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<String>("locale") ?: "en-US", result)
            "stop" -> { stop(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun emit(type: String, fields: Map<String, Any?> = emptyMap()) {
        main.post { sink?.success(mapOf("type" to type) + fields) }
    }

    private fun start(localeTag: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) {
            val message = "External audio recognition requires Android 13 or newer."
            emit("error", mapOf("code" to "unsupported_api", "message" to message))
            result.error("unsupported_api", message, null)
            return
        }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            val message = "Microphone permission is required for handsfree listening."
            emit("error", mapOf("code" to "permission_denied", "message" to message))
            result.error("permission_denied", message, null)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            val message = "No Android speech recognition service is available."
            emit("error", mapOf("code" to "recognizer_unavailable", "message" to message))
            result.error("recognizer_unavailable", message, null)
            return
        }
        stop()
        try {
            previousAudioMode = audioManager.mode
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            val minBuffer = AudioRecord.getMinBufferSize(
                SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
            )
            if (minBuffer <= 0) throw IllegalStateException("16 kHz microphone capture is unavailable.")
            val audio = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build())
                .setBufferSizeInBytes(maxOf(minBuffer * 2, SAMPLE_RATE))
                .build()
            if (audio.state != AudioRecord.STATE_INITIALIZED) {
                audio.release()
                throw IllegalStateException("Could not initialize VOICE_COMMUNICATION microphone capture.")
            }
            recorder = audio
            aec = if (AcousticEchoCanceler.isAvailable()) AcousticEchoCanceler.create(audio.audioSessionId) else null
            if (aec == null) throw IllegalStateException("This device does not provide acoustic echo cancellation.")
            aec?.enabled = true
            if (aec?.enabled != true) throw IllegalStateException("Android acoustic echo cancellation could not be enabled.")
            noiseSuppressor = try {
                if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(audio.audioSessionId)?.also {
                    it.enabled = true
                } else null
            } catch (_: Exception) {
                null // optional; echo cancellation remains required.
            }
            val (readEnd, writeEnd) = ParcelFileDescriptor.createPipe()
            pipeRead = readEnd
            pipeWrite = writeEnd
            val sessionGeneration = generation
            recognizer = SpeechRecognizer.createSpeechRecognizer(context).also {
                it.setRecognitionListener(listenerFor(sessionGeneration))
            }
            val locale = Locale.forLanguageTag(localeTag)
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale.toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readEnd)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, SAMPLE_RATE)
                // One recognizer session can emit final segments while the supplied pipe remains open.
                putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            }
            running.set(true)
            audio.startRecording()
            if (audio.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                throw IllegalStateException("Microphone capture did not start.")
            }
            captureThread = Thread({ pumpAudio(audio, writeEnd, sessionGeneration) }, "duplex-pcm-capture").apply { start() }
            recognizer?.startListening(intent)
            android.util.Log.i("DuplexSpeech", "Echo-cancelled microphone started for segmented recognition")
            emit("ready", mapOf(
                "locale" to locale.toLanguageTag(),
                "echoCancellation" to (aec?.enabled == true),
                "noiseSuppression" to (noiseSuppressor?.enabled == true)
            ))
            result.success(null)
        } catch (e: Exception) {
            stop()
            val message = e.message ?: "Could not start external audio recognition."
            emit("error", mapOf("code" to "start_failed", "message" to message))
            result.error("start_failed", message, null)
        }
    }

    private fun pumpAudio(audio: AudioRecord, output: ParcelFileDescriptor, sessionGeneration: Int) {
        val stream = ParcelFileDescriptor.AutoCloseOutputStream(output)
        val buffer = ByteArray(3_200)
        try {
            while (running.get() && generation == sessionGeneration) {
                val count = audio.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (count > 0) {
                    val gatedFrames = speechGate.processPcm16(buffer, count, SystemClock.elapsedRealtime())
                    gatedFrames.forEach(stream::write)
                    if (gatedFrames.isNotEmpty()) stream.flush()
                } else if (count < 0) {
                    throw IOException("Microphone read failed ($count).")
                }
            }
        } catch (e: Exception) {
            if (running.get() && generation == sessionGeneration) {
                emit("error", mapOf("code" to "audio_stream", "message" to (e.message ?: "Audio stream stopped.")))
                main.post { stop() }
            }
        } finally {
            try { stream.close() } catch (_: Exception) { }
        }
    }

    private fun listenerFor(sessionGeneration: Int) = object : RecognitionListener {
        private fun current() = sessionGeneration == generation
        override fun onReadyForSpeech(params: android.os.Bundle?) { if (current()) emit("status", mapOf("status" to "listening", "message" to "Recognizer ready.")) }
        override fun onBeginningOfSpeech() { if (current()) emit("status", mapOf("status" to "listening", "message" to "Speech detected.")) }
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() { if (current()) emit("status", mapOf("status" to "listening", "message" to "Speech segment ended.")) }
        override fun onError(error: Int) {
            if (!current()) return
            if (error == ERROR_NO_MATCH || error == ERROR_SPEECH_TIMEOUT) {
                emit("status", mapOf("status" to "done", "message" to "No speech recognized."))
                return
            }
            android.util.Log.w("DuplexSpeech", "Recognizer error code=$error")
            val message = when (error) {
                ERROR_AUDIO -> "Android recognizer rejected the external audio stream."
                ERROR_CLIENT -> "Android recognition session ended unexpectedly."
                ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is missing."
                ERROR_NETWORK, ERROR_NETWORK_TIMEOUT -> "Speech recognition network error."
                ERROR_NO_MATCH, ERROR_SPEECH_TIMEOUT -> "No speech was recognized."
                ERROR_RECOGNIZER_BUSY -> "Android speech recognizer is busy."
                ERROR_SERVER -> "Android speech recognition service failed."
                else -> "Android speech recognition failed (code $error)."
            }
            emit("error", mapOf("code" to "recognizer_$error", "message" to message))
        }
        override fun onResults(results: android.os.Bundle?) {
            if (current()) {
                emitRecognition("final", results)
                emit("status", mapOf("status" to "done"))
            }
        }
        override fun onPartialResults(partialResults: android.os.Bundle?) { if (current()) emitRecognition("partial", partialResults) }
        override fun onSegmentResults(segmentResults: android.os.Bundle) { if (current()) emitRecognition("segment", segmentResults) }
        override fun onEndOfSegmentedSession() { if (current()) emit("status", mapOf("status" to "done")) }
        override fun onEvent(eventType: Int, params: android.os.Bundle?) {}
    }

    private fun emitRecognition(type: String, bundle: android.os.Bundle?) {
        val maxAgeMs = if (type == "partial") 3_000L else 6_000L
        if (!speechGate.hasRecentSpeech(SystemClock.elapsedRealtime(), maxAgeMs)) return
        val text = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
        emit(type, mapOf("text" to text))
    }

    fun stop(notify: Boolean = false) {
        val wasRunning = running.get()
        generation++
        running.set(false)
        try { recognizer?.cancel() } catch (_: Exception) { }
        try { recognizer?.destroy() } catch (_: Exception) { }
        recognizer = null
        try { recorder?.stop() } catch (_: Exception) { }
        try { recorder?.release() } catch (_: Exception) { }
        recorder = null
        try { aec?.enabled = false; aec?.release() } catch (_: Exception) { }
        aec = null
        try { noiseSuppressor?.enabled = false; noiseSuppressor?.release() } catch (_: Exception) { }
        noiseSuppressor = null
        speechGate.reset()
        try { pipeWrite?.close() } catch (_: Exception) { }
        try { pipeRead?.close() } catch (_: Exception) { }
        pipeWrite = null
        pipeRead = null
        captureThread = null
        previousAudioMode?.let { audioManager.mode = it }
        previousAudioMode = null
        if (notify && wasRunning) emit("status", mapOf("status" to "done", "message" to "App moved to background."))
    }
}
