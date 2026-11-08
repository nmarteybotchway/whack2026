package com.example.hackathon

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

class SpeechActivityGateTest {
    private val frameBytes = 640 // 20 ms, 16 kHz, mono PCM16

    @Test
    fun silenceAndLowRoomNoiseStayGated() {
        val gate = SpeechActivityGate()
        val output = feed(gate, frames = 250) { 0.001 }
        assertTrue(output.isNotEmpty())
        assertTrue(output.all { it.all { sample -> sample == 0.toByte() } })
        assertFalse(gate.hasRecentSpeech(5_000, 3_000))
    }

    @Test
    fun shortClickDoesNotQualifyAsSpeech() {
        val gate = SpeechActivityGate()
        val output = mutableListOf<ByteArray>()
        var time = 0L
        repeat(5) { // 100 ms transient, shorter than the 140 ms attack.
            output += gate.processPcm16(frame(0.35), frameBytes, time)
            time += 20
        }
        repeat(250) {
            output += gate.processPcm16(frame(0.0), frameBytes, time)
            time += 20
        }
        assertTrue(output.all { it.all { sample -> sample == 0.toByte() } })
        assertFalse(gate.hasRecentSpeech(time, 3_000))
    }

    @Test
    fun sustainedChangingSpeechOpensGateAndPreservesPreroll() {
        val gate = SpeechActivityGate()
        val output = feed(gate, frames = 25) { 0.0 }.toMutableList()
        var time = 500L
        repeat(100) { index ->
            // Alternating levels model syllabic modulation and should not be
            // learned as a stationary fan/noise floor.
            val rms = if ((index / 5) % 2 == 0) 0.08 else 0.035
            output += gate.processPcm16(frame(rms), frameBytes, time)
            time += 20
        }
        assertTrue(gate.hasRecentSpeech(time, 3_000))
        val firstAudibleOutputFrame = output.indexOfFirst { chunk -> chunk.any { it != 0.toByte() } }
        assertTrue("qualified speech and its buffered start should pass", firstAudibleOutputFrame >= 0)
        assertTrue("200 ms look-ahead should preserve the onset at its delayed position", firstAudibleOutputFrame == 25)
        assertTrue("the delay line must not drop frames", output.size == 25 + 100 - 10)
    }

    @Test
    fun hangoverClosesAfterSilenceAndRecognitionWindowExpires() {
        val gate = SpeechActivityGate()
        var time = 0L
        repeat(75) {
            gate.processPcm16(frame(0.08), frameBytes, time)
            time += 20
        }
        assertTrue(gate.hasRecentSpeech(time, 3_000))
        repeat(400) {
            gate.processPcm16(frame(0.0), frameBytes, time)
            time += 20
        }
        assertFalse(gate.hasRecentSpeech(time, 3_000))
        assertFalse(gate.hasRecentSpeech(time, 6_000))
    }

    @Test
    fun stableAmbientNoiseIsLearnedAndDoesNotKeepActivityAlive() {
        val gate = SpeechActivityGate()
        var time = 0L
        // Stationary fan-like broadband energy above the absolute floor.
        repeat(500) {
            gate.processPcm16(frame(0.014), frameBytes, time)
            time += 20
        }
        assertFalse(gate.hasRecentSpeech(time, 3_000))
    }

    @Test
    fun resetClearsNoiseAndSpeechStateBetweenSessions() {
        val gate = SpeechActivityGate(initialNoiseFloorDb = -50.0)
        var time = 0L
        repeat(20) {
            gate.processPcm16(frame(0.08), frameBytes, time)
            time += 20
        }
        assertTrue(gate.hasRecentSpeech(time, 3_000))
        gate.reset()
        assertFalse(gate.hasRecentSpeech(time, 3_000))
        val output = feed(gate, frames = 30) { 0.0 }
        assertTrue(output.all { it.all { sample -> sample == 0.toByte() } })
    }

    private fun feed(gate: SpeechActivityGate, frames: Int, rms: (Int) -> Double): List<ByteArray> {
        val output = mutableListOf<ByteArray>()
        repeat(frames) { index ->
            output += gate.processPcm16(frame(rms(index)), frameBytes, index * 20L)
        }
        return output
    }

    /** Sine-wave PCM16 with the requested approximate RMS amplitude. */
    private fun frame(rms: Double): ByteArray {
        val peak = (rms * 1.4142 * Short.MAX_VALUE).toInt().coerceIn(0, Short.MAX_VALUE.toInt())
        val bytes = ByteArray(frameBytes)
        repeat(frameBytes / 2) { index ->
            val sample = (peak * sin(2.0 * PI * 440.0 * index / 16_000.0)).toInt().toShort().toInt()
            bytes[index * 2] = sample.toByte()
            bytes[index * 2 + 1] = (sample shr 8).toByte()
        }
        return bytes
    }
}
