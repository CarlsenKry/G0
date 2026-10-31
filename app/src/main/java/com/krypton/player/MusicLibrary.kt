package com.krypton.player

import android.content.Context
import android.provider.MediaStore

data class Track(
    val id: Long,
    val title: String,
    val artist: String,
    val uri: android.net.Uri
)

object MusicLibrary {
    fun query(context: Context): List<Track> {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val result = mutableListOf<Track>()
        context.contentResolver.query(
            collection, projection, selection, null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                result += Track(
                    id,
                    cursor.getString(titleCol) ?: "Unknown title",
                    cursor.getString(artistCol)?.takeIf { it != "<unknown>" } ?: "Unknown artist",
                    android.content.ContentUris.withAppendedId(collection, id)
                )
            }
        }
        return result
    }
}
