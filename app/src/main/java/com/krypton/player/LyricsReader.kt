package com.krypton.player

import android.content.ContentResolver
import android.net.Uri
import java.io.BufferedReader

data class LyricLine(val timeMs: Long?, val text: String)

object LyricsReader {
    private val lrcPattern = Regex("""\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?]""")

    /** Parse LRC timestamps; lines without timestamps remain readable as plain lyrics. */
    fun parse(text: String): List<LyricLine> {
        val output = mutableListOf<LyricLine>()
        text.lineSequence().forEach { line ->
            val stamps = lrcPattern.findAll(line).toList()
            val lyric = line.replace(lrcPattern, "").trim()
            if (stamps.isEmpty()) {
                if (lyric.isNotBlank()) output += LyricLine(null, lyric)
            } else {
                stamps.forEach { match ->
                    val minutes = match.groupValues[1].toLong()
                    val seconds = match.groupValues[2].toLong()
                    val fraction = match.groupValues[3].padEnd(3, '0').ifBlank { "0" }.toLong()
                    output += LyricLine(minutes * 60_000 + seconds * 1_000 + fraction, lyric)
                }
            }
        }
        return output.sortedBy { it.timeMs ?: Long.MAX_VALUE }
    }

    /** Reads a selected .lrc/.txt document. Use the Storage Access Framework picker in the UI. */
    fun readDocument(resolver: ContentResolver, uri: Uri): List<LyricLine> =
        resolver.openInputStream(uri)?.bufferedReader()?.use(BufferedReader::readText)
            ?.let(::parse).orEmpty()

    /** Sidecar candidates for a track named song.mp3: song.lrc and song.txt.
     * Access is intentionally delegated to SAF/document-tree permissions on modern Android.
     */
    fun sidecarNames(audioDisplayName: String): List<String> {
        val stem = audioDisplayName.substringBeforeLast('.', audioDisplayName)
        return listOf("$stem.lrc", "$stem.txt")
    }

    /** Extract common embedded lyric metadata keys when present in a metadata map. */
    fun fromEmbeddedMetadata(metadata: Map<String, String>): List<LyricLine> {
        val value = metadata.entries.firstOrNull {
            it.key.equals("lyrics", true) || it.key.equals("unsyncedlyrics", true) ||
                it.key.equals("uslt", true) || it.key.equals("sylt", true)
        }?.value ?: return emptyList()
        return parse(value)
    }
}
