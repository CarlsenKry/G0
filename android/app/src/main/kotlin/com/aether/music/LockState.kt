package com.aether.music

import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArrayList

/**
 * In-memory mirror of the player state that the Dart side pushes to the native
 * lock screen (see lib/services/lockscreen_service.dart). It lives as long as the
 * app process, so the lock screen can be shown even when the main activity is gone.
 */
object LockState {
    @Volatile var channel: MethodChannel? = null

    @Volatile var enabled = false
    @Volatile var hasTrack = false
    @Volatile var playing = false

    var title = ""
    var artist = ""
    var album = ""
    var coverPath: String? = null
    var accent: Int = 0xFF00F0FF.toInt()
    var favorite = false
    var shuffle = false
    var repeat = "off"
    var durationMs = 0L
    var lyrics: List<Pair<Double, String>> = emptyList()
    var queue: List<String> = emptyList()
    var opts: Map<String, Any?> = emptyMap()

    private var basePositionMs = 0L
    private var baseAt = 0L

    val listeners = CopyOnWriteArrayList<Runnable>()

    fun apply(m: Map<*, *>) {
        enabled = m["enabled"] == true
        hasTrack = m["hasTrack"] == true
        playing = m["playing"] == true
        title = (m["title"] as? String) ?: ""
        artist = (m["artist"] as? String) ?: ""
        album = (m["album"] as? String) ?: ""
        coverPath = m["coverPath"] as? String
        accent = (m["accent"] as? Number)?.toInt() ?: accent
        favorite = m["favorite"] == true
        shuffle = m["shuffle"] == true
        repeat = (m["repeat"] as? String) ?: "off"
        durationMs = (m["durationMs"] as? Number)?.toLong() ?: 0L
        basePositionMs = (m["positionMs"] as? Number)?.toLong() ?: 0L
        baseAt = SystemClock.elapsedRealtime()

        val rawLyrics = m["lyrics"] as? List<*>
        val parsed = ArrayList<Pair<Double, String>>()
        if (rawLyrics != null) {
            for (entry in rawLyrics) {
                val pair = entry as? List<*> ?: continue
                if (pair.size < 2) continue
                val time = (pair[0] as? Number)?.toDouble() ?: 0.0
                val text = (pair[1] as? String) ?: ""
                parsed.add(Pair(time, text))
            }
        }
        lyrics = parsed

        val rawQueue = m["queue"] as? List<*>
        queue = rawQueue?.map { it?.toString() ?: "" } ?: emptyList()

        val rawOpts = m["opts"] as? Map<*, *>
        val o = HashMap<String, Any?>()
        if (rawOpts != null) {
            for ((k, v) in rawOpts) {
                if (k is String) o[k] = v
            }
        }
        opts = o
        notifyChanged()
    }

    fun flag(key: String, def: Boolean = true): Boolean = (opts[key] as? Boolean) ?: def

    fun number(key: String, def: Int): Int = (opts[key] as? Number)?.toInt() ?: def

    fun text(key: String, def: String): String = (opts[key] as? String) ?: def

    fun positionMs(): Long {
        var p = basePositionMs
        if (playing) p += SystemClock.elapsedRealtime() - baseAt
        if (durationMs > 0 && p > durationMs) p = durationMs
        return if (p < 0) 0L else p
    }

    fun optimisticPlaying(value: Boolean) {
        basePositionMs = positionMs()
        baseAt = SystemClock.elapsedRealtime()
        playing = value
        notifyChanged()
    }

    fun optimisticSeek(ms: Long) {
        var target = ms
        if (target < 0) target = 0
        if (durationMs > 0 && target > durationMs) target = durationMs
        basePositionMs = target
        baseAt = SystemClock.elapsedRealtime()
        notifyChanged()
    }

    fun optimisticFavorite(value: Boolean) {
        favorite = value
        notifyChanged()
    }

    /** Sends a transport command to the Dart player (runs in the main engine). */
    fun command(name: String, value: Any? = null) {
        val args = HashMap<String, Any?>()
        args["name"] = name
        args["value"] = value
        try {
            channel?.invokeMethod("lockCommand", args)
        } catch (_: Throwable) {
        }
    }

    private fun notifyChanged() {
        for (l in listeners) l.run()
    }
}
