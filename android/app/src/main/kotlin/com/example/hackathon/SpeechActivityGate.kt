package com.example.hackathon

import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Energy based PCM gate with a constant 200 ms delay line. The delay lets us
 * preserve the start of a sustained utterance after its attack qualifies while
 * still sending a continuous stream (closed frames are zeroed, never removed).
 * It is a noise gate, not a speech classifier; tuning is deliberately exposed
 * through named constants for device calibration.
 */
internal class SpeechActivityGate(
    private val sampleRate: Int = 16_000,
    private val frameMillis: Int = 20,
    private val prerollMillis: Int = 200,
    private val attackMillis: Int = 140,
    private val releaseMillis: Int = 700,
    private val absoluteFloorDb: Double = -42.0,
    private val noiseMarginDb: Double = 10.0,
    initialNoiseFloorDb: Double = -60.0,
) {
    private data class Frame(val pcm: ByteArray, var passThrough: Boolean = false)

    private val frameBytes = sampleRate * frameMillis / 1_000 * 2
    private val delayFrames = prerollMillis / frameMillis
    private val attackFrames = (attackMillis + frameMillis - 1) / frameMillis
    private val releaseFrames = (releaseMillis + frameMillis - 1) / frameMillis
    private val delay = ArrayDeque<Frame>()
    private val levelHistory = ArrayDeque<Double>()
    private var remainder = ByteArray(0)
    private val initialNoiseFloor = initialNoiseFloorDb
    private var noiseFloorDb = initialNoiseFloorDb
    private var gateOpen = false
    private var attackCount = 0
    private var belowThresholdCount = 0
    private var stationaryFrames = 0

    @Volatile
    private var lastQualifiedSpeechMs: Long = Long.MIN_VALUE

    /** Returns only frames whose 200 ms look-ahead delay has elapsed. */
    @Synchronized
    fun processPcm16(input: ByteArray, length: Int, nowMs: Long): List<ByteArray> {
        require(length in 0..input.size)
        val combined = ByteArray(remainder.size + length)
        remainder.copyInto(combined)
        input.copyInto(combined, remainder.size, 0, length)
        val completeBytes = combined.size - combined.size % frameBytes
        remainder = combined.copyOfRange(completeBytes, combined.size)
        val output = ArrayList<ByteArray>()
        var offset = 0
        while (offset < completeBytes) {
            val pcm = combined.copyOfRange(offset, offset + frameBytes)
            val frame = Frame(pcm)
            updateGate(frame, rmsDb(pcm), nowMs)
            delay.addLast(frame)
            if (delay.size > delayFrames) {
                val ready = delay.removeFirst()
                output += if (ready.passThrough) ready.pcm else ByteArray(frameBytes)
            }
            offset += frameBytes
        }
        return output
    }

    private fun updateGate(frame: Frame, levelDb: Double, nowMs: Long) {
        levelHistory.addLast(levelDb)
        if (levelHistory.size > 40) levelHistory.removeFirst()
        val stableLevel = levelHistory.size == 40 && levelHistory.maxOrNull()!! - levelHistory.minOrNull()!! <= 2.5
        stationaryFrames = if (stableLevel) stationaryFrames + 1 else 0

        val threshold = max(absoluteFloorDb, noiseFloorDb + noiseMarginDb)
        val aboveThreshold = levelDb >= threshold

        if (!gateOpen) {
            // Learn a rising ambient floor while closed. Faster fall lets the
            // gate recover quickly when the environment quiets down.
            val alpha = if (levelDb > noiseFloorDb) 0.02 else 0.08
            noiseFloorDb += alpha * (levelDb - noiseFloorDb)
            if (aboveThreshold) {
                attackCount++
                if (attackCount >= attackFrames) {
                    gateOpen = true
                    belowThresholdCount = 0
                    // Release buffered preroll and attack so the first phoneme
                    // is retained. This queue is bounded to 200 ms.
                    delay.forEach { it.passThrough = true }
                    frame.passThrough = true
                    lastQualifiedSpeechMs = nowMs
                }
            } else {
                attackCount = 0 // rejects short impulses such as clicks.
            }
            return
        }

        if (aboveThreshold) {
            belowThresholdCount = 0
            frame.passThrough = true
            lastQualifiedSpeechMs = nowMs
            // Do not train on speech. Only a level that remains nearly flat
            // for >= 800 ms is treated as stationary ambience (fan, hum, etc.).
            if (stationaryFrames >= 40) {
                noiseFloorDb += 0.18 * (levelDb - noiseFloorDb)
            }
        } else {
            belowThresholdCount++
            frame.passThrough = true // short gaps and trailing consonants.
            val alpha = if (levelDb > noiseFloorDb) 0.02 else 0.08
            noiseFloorDb += alpha * (levelDb - noiseFloorDb)
            if (belowThresholdCount >= releaseFrames) {
                gateOpen = false
                attackCount = 0
                // The release tail has already been emitted; subsequent
                // frames are zeroed unless a new attack qualifies.
            }
        }
    }

    /** Speech activity qualification for delayed recognizer callbacks. */
    fun hasRecentSpeech(nowMs: Long, maxAgeMs: Long): Boolean {
        val last = lastQualifiedSpeechMs
        return last != Long.MIN_VALUE && nowMs >= last && nowMs - last <= maxAgeMs
    }

    @Synchronized
    fun reset() {
        delay.clear()
        levelHistory.clear()
        remainder = ByteArray(0)
        noiseFloorDb = initialNoiseFloor
        gateOpen = false
        attackCount = 0
        belowThresholdCount = 0
        stationaryFrames = 0
        lastQualifiedSpeechMs = Long.MIN_VALUE
    }

    private fun rmsDb(pcm: ByteArray): Double {
        var sumSquares = 0.0
        var sampleCount = pcm.size / 2
        if (sampleCount == 0) return -120.0
        var offset = 0
        while (offset + 1 < pcm.size) {
            val sample = ((pcm[offset + 1].toInt() shl 8) or (pcm[offset].toInt() and 0xff)).toShort().toInt()
            val normalized = sample / 32768.0
            sumSquares += normalized * normalized
            offset += 2
        }
        val rms = sqrt(sumSquares / sampleCount).coerceAtLeast(1e-6)
        return 20.0 * ln(rms) / ln(10.0)
    }
}
