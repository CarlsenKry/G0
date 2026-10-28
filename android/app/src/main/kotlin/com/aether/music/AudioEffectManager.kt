package com.aether.music

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.roundToInt

/**
 * Process-level owner for audio effects attached to just_audio session IDs.
 *
 * This deliberately does not belong to MainActivity: Android's media playback
 * foreground service can keep playing after the Activity (and Flutter UI) is
 * destroyed. Holding effects here keeps them alive for the process/audio-session
 * lifetime. Session-keyed reuse handles crossfades; a small insertion-order cap
 * bounds stale session handles if a player is recreated.
 */
object AudioEffectManager {
    private data class SessionAudioEffects(
        val equalizer: Equalizer,
        val bassBoost: BassBoost,
        val loudnessEnhancer: LoudnessEnhancer
    )

    private val effectsBySession = LinkedHashMap<Int, SessionAudioEffects>()

    @Synchronized
    fun applyAudioEffects(
        sessionId: Int,
        bandLevelsDb: List<Double>,
        preampDb: Double,
        bassPercent: Int,
        enabled: Boolean,
        volumeStabilizer: Boolean,
        replayGainDb: Double?,
        replayGainPeak: Double?
    ): Boolean {
        if (sessionId <= 0) return false
        return try {
            var fx = effectsBySession[sessionId]
            if (fx == null) {
                // Two live players cover ordinary playback and crossfades. Keep some
                // headroom for devices that briefly rotate session IDs while switching.
                if (effectsBySession.size >= 4) {
                    val oldest = effectsBySession.keys.firstOrNull { it != sessionId }
                    if (oldest != null) releaseAudioEffectsForSessionLocked(oldest)
                }
                fx = SessionAudioEffects(
                    Equalizer(0, sessionId),
                    BassBoost(0, sessionId),
                    LoudnessEnhancer(sessionId)
                )
                effectsBySession[sessionId] = fx
            }

            val eq = fx.equalizer
            val count = eq.numberOfBands.toInt()
            val range = eq.bandLevelRange
            val targetFrequencies = doubleArrayOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0)
            val source = if (bandLevelsDb.size >= 10) bandLevelsDb.take(10) else bandLevelsDb + List(10 - bandLevelsDb.size) { 0.0 }
            val buckets = Array(count) { ArrayList<Double>() }

            // Map ten UI bands onto however many physical bands this device exposes.
            for (uiIndex in targetFrequencies.indices) {
                var nearestBand = 0
                var nearestDistance = Double.MAX_VALUE
                for (nativeIndex in 0 until count) {
                    val centerHz = (eq.getCenterFreq(nativeIndex.toShort()).toDouble() / 1000.0).coerceAtLeast(1.0)
                    val distance = abs(ln(centerHz) - ln(targetFrequencies[uiIndex]))
                    if (distance < nearestDistance) {
                        nearestDistance = distance
                        nearestBand = nativeIndex
                    }
                }
                buckets[nearestBand].add(source[uiIndex].coerceIn(-12.0, 12.0))
            }
            for (index in 0 until count) {
                val values = buckets[index]
                val db = if (values.isEmpty()) 0.0 else values.average()
                val millibels = (db * 100.0).roundToInt().coerceIn(range[0].toInt(), range[1].toInt())
                eq.setBandLevel(index.toShort(), millibels.toShort())
            }
            eq.enabled = enabled

            fx.bassBoost.setStrength((bassPercent.coerceIn(0, 100) * 10).toShort())
            fx.bassBoost.enabled = enabled && bassPercent > 0

            // ReplayGain stores a correction in dB. Reduce it if the tagged peak
            // would exceed full scale; this preserves headroom.
            val hasReplayGain = volumeStabilizer && replayGainDb != null
            val replayGainCorrectionDb = if (hasReplayGain) replayGainDb!!.coerceIn(-18.0, 12.0) else 0.0
            val preampCorrectionDb = if (enabled) preampDb.coerceIn(-12.0, 12.0) else 0.0
            var targetCorrectionDb = (preampCorrectionDb + replayGainCorrectionDb).coerceIn(-12.0, 12.0)
            if (hasReplayGain) {
                if (replayGainPeak != null && replayGainPeak > 0.0) {
                    val maximumSafeGainDb = -20.0 * log10(replayGainPeak)
                    targetCorrectionDb = minOf(targetCorrectionDb, maximumSafeGainDb)
                } else {
                    targetCorrectionDb = minOf(targetCorrectionDb, 0.0)
                }
            }
            // Android's LoudnessEnhancer only boosts. Negative ReplayGain is applied
            // as per-player volume attenuation in Dart.
            val targetGainMb = (maxOf(0.0, targetCorrectionDb) * 100.0).roundToInt().coerceIn(0, 1200)
            fx.loudnessEnhancer.setTargetGain(targetGainMb)
            fx.loudnessEnhancer.enabled = targetGainMb > 0
            true
        } catch (_: Throwable) {
            releaseAudioEffectsForSessionLocked(sessionId)
            false
        }
    }

    /** Explicit emergency cleanup only; not called from Activity/UI disposal. */
    @Synchronized
    fun releaseAll() {
        effectsBySession.keys.toList().forEach(::releaseAudioEffectsForSessionLocked)
    }

    private fun releaseAudioEffectsForSessionLocked(sessionId: Int) {
        val fx = effectsBySession.remove(sessionId) ?: return
        try { fx.equalizer.release() } catch (_: Throwable) {}
        try { fx.bassBoost.release() } catch (_: Throwable) {}
        try { fx.loudnessEnhancer.release() } catch (_: Throwable) {}
    }
}
