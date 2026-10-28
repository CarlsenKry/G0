package com.aether.music

import android.Manifest
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.log10
import kotlin.math.pow

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.aether.music/native"
    private val permissionRequestCode = 4711
    private val importPlaylistRequestCode = 4712
    private val exportPlaylistRequestCode = 4713
    private val selectLyricsFolderRequestCode = 4714
    private var pendingDocumentResult: MethodChannel.Result? = null
    private var pendingExportContent: String? = null

    private var pendingPermissionResult: MethodChannel.Result? = null
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val coverExecutor = Executors.newFixedThreadPool(2)
    private val loudnessScanExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var loudnessScanGeneration: Long = 0L

    // Audio-effect calls can block while the player swaps sources. Keep them off
    // the UI thread and serialize them on this single worker.
    private val fxExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val nativeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        nativeChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            handleCall(call, result)
        }
        // The custom lock screen sends transport commands back to Dart through this channel.
        LockState.channel = nativeChannel


    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != importPlaylistRequestCode &&
            requestCode != exportPlaylistRequestCode &&
            requestCode != selectLyricsFolderRequestCode
        ) return
        val result = pendingDocumentResult ?: return
        pendingDocumentResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            pendingExportContent = null
            result.success(if (requestCode == exportPlaylistRequestCode) false else null)
            return
        }
        val uri = data.data!!
        try {
            when (requestCode) {
                importPlaylistRequestCode -> {
                    val content = contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                    result.success(content)
                }
                exportPlaylistRequestCode -> {
                    val content = pendingExportContent ?: ""
                    pendingExportContent = null
                    contentResolver.openOutputStream(uri, "wt")?.bufferedWriter(Charsets.UTF_8)?.use { it.write(content) }
                        ?: throw IllegalStateException("Could not write the selected file")
                    result.success(true)
                }
                selectLyricsFolderRequestCode -> {
                    val persistableFlags = data.flags and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    if ((persistableFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION) == 0) {
                        throw IllegalStateException("The selected folder did not grant read access")
                    }
                    contentResolver.takePersistableUriPermission(uri, persistableFlags)
                    val prefs = getSharedPreferences("external_lyrics", MODE_PRIVATE)
                    val oldTree = prefs.getString("tree_uri", null)
                    if (oldTree != null && oldTree != uri.toString()) {
                        try {
                            contentResolver.releasePersistableUriPermission(
                                Uri.parse(oldTree),
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            )
                        } catch (_: Throwable) { /* The old grant may already be revoked. */ }
                    }
                    prefs.edit().putString("tree_uri", uri.toString()).apply()
                    LyricsFileMonitor.setTreeUri(this, uri)
                    result.success(lyricsFolderLabel(uri))
                }
            }
        } catch (e: Throwable) {
            pendingExportContent = null
            result.error("document_io", "Could not read or write the selected document", e.message)
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermissions" -> result.success(permissionState())
            "requestPermissions" -> requestAllPermissions(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "openAppSettings" -> {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)
                )
                startActivity(intent)
                result.success(true)
            }
            "scanTracks" -> scanTracks(result)
            "getLyricsFolder" -> result.success(savedLyricsFolderLabel())
            "getExternalLyricsChangeToken" -> result.success(LyricsFileMonitor.changeToken(this))
            "selectLyricsFolder" -> {
                if (pendingDocumentResult != null) {
                    result.error("busy", "Another document operation is running", null)
                } else {
                    pendingDocumentResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    try { startActivityForResult(intent, selectLyricsFolderRequestCode) }
                    catch (e: Throwable) {
                        pendingDocumentResult = null
                        result.error("picker", "Could not open folder picker", e.message)
                    }
                }
            }
            "readExternalLyrics" -> {
                val id = call.argument<String>("id")
                if (id == null) result.success(null) else readExternalLyrics(id, result)
            }
            "importM3u" -> {
                if (pendingDocumentResult != null) {
                    result.error("busy", "Another document operation is running", null)
                } else {
                    pendingDocumentResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/x-mpegurl", "audio/mpegurl", "application/x-mpegURL", "text/plain"))
                    }
                    try { startActivityForResult(intent, importPlaylistRequestCode) }
                    catch (e: Throwable) { pendingDocumentResult = null; result.error("picker", "Could not open file picker", e.message) }
                }
            }
            "exportM3u" -> {
                if (pendingDocumentResult != null) {
                    result.error("busy", "Another document operation is running", null)
                } else {
                    val content = call.argument<String>("content")
                    val filename = call.argument<String>("filename") ?: "playlist.m3u"
                    if (content == null) {
                        result.error("argument", "Playlist content is missing", null)
                    } else {
                        pendingDocumentResult = result
                        pendingExportContent = content
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/x-mpegurl"
                            putExtra(Intent.EXTRA_TITLE, if (filename.endsWith(".m3u", true)) filename else "$filename.m3u")
                        }
                        try { startActivityForResult(intent, exportPlaylistRequestCode) }
                        catch (e: Throwable) { pendingDocumentResult = null; pendingExportContent = null; result.error("picker", "Could not open save dialog", e.message) }
                    }
                }
            }
            "loadCover" -> {
                val id = call.argument<String>("id")
                val size = call.argument<Int>("size") ?: 512
                if (id == null) {
                    result.success(null)
                } else {
                    loadCover(id, size, result)
                }
            }
            "readHead" -> {
                val id = call.argument<String>("id")
                val maxBytes = call.argument<Int>("maxBytes") ?: 524288
                if (id == null) {
                    result.success(null)
                } else {
                    readHead(id, maxBytes, result)
                }
            }
            "readReplayGain" -> {
                val id = call.argument<String>("id")
                if (id == null) result.success(emptyMap<String, Any?>())
                else readReplayGain(id, result)
            }
            "analyzeLoudness" -> {
                val id = call.argument<String>("id")
                val targetLufs = call.argument<Number>("targetLufs")?.toDouble() ?: -14.0
                if (id == null) result.success(mapOf("success" to false))
                else analyzeLoudness(id, targetLufs, result)
            }
            "cancelLoudnessScan" -> {
                // Incrementing the generation makes the active decoder exit at its next
                // input/output checkpoint; no new scan is allowed by Dart while disabled.
                loudnessScanGeneration++
                result.success(true)
            }
            "applyAudioEffects" -> {
                val sessionId = call.argument<Int>("sessionId") ?: 0
                val bands = call.argument<List<Number>>("bandsDb")?.map { it.toDouble() } ?: emptyList()
                val preamp = call.argument<Number>("preampDb")?.toDouble() ?: 0.0
                val bass = call.argument<Int>("bassBoost") ?: 0
                val enabled = call.argument<Boolean>("enabled") ?: true
                val volumeStabilizer = call.argument<Boolean>("volumeStabilizer") ?: false
                val replayGainDb = call.argument<Number>("replayGainDb")?.toDouble()
                val replayGainPeak = call.argument<Number>("replayGainPeak")?.toDouble()
                runFx(result) {
                    AudioEffectManager.applyAudioEffects(
                        sessionId, bands, preamp, bass, enabled, volumeStabilizer, replayGainDb, replayGainPeak
                    )
                }
            }
            "lockscreenSync" -> {
                val state = call.arguments as? Map<*, *>
                if (state != null) LockState.apply(state)
                result.success(true)
            }
            "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
            "openOverlaySettings" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
                result.success(true)
            }
            "previewLockscreen" -> {
                startActivity(LockLauncher.buildIntent(this, true))
                result.success(true)
            }
            "releaseAudioEffects" -> {
                runFx(result) {
                    AudioEffectManager.releaseAll()
                    true
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runFx(result: MethodChannel.Result, block: () -> Boolean) {
        try {
            fxExecutor.execute {
                val ok = try {
                    block()
                } catch (_: Throwable) {
                    false
                }
                runOnUiThread {
                    try {
                        result.success(ok)
                    } catch (_: Throwable) {
                    }
                }
            }
        } catch (_: Throwable) {
            result.success(false)
        }
    }

    // ---------------------------------------------------------------- permissions

    private fun mediaPermission(): String {
        return if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    private fun has(permission: String): Boolean {
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun permissionState(): HashMap<String, Boolean> {
        val state = HashMap<String, Boolean>()
        state["media"] = has(mediaPermission())
        state["notifications"] = if (Build.VERSION.SDK_INT >= 33) {
            has(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            true
        }
        return state
    }

    private fun requestAllPermissions(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already running", null)
            return
        }
        val missing = ArrayList<String>()
        if (!has(mediaPermission())) missing.add(mediaPermission())

        if (missing.isEmpty()) {
            result.success(permissionState())
            return
        }
        pendingPermissionResult = result
        requestPermissions(missing.toTypedArray(), permissionRequestCode)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || has(Manifest.permission.POST_NOTIFICATIONS)) {
            result.success(permissionState())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already running", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val pending = pendingPermissionResult
            pendingPermissionResult = null
            pending?.success(permissionState())
        }
    }

    // ---------------------------------------------------------------- library scan

    private fun scanTracks(result: MethodChannel.Result) {
        scanExecutor.execute {
            try {
                val list = ArrayList<HashMap<String, Any?>>()
                val media = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                val projection = ArrayList<String>()
                projection.add(MediaStore.Audio.Media._ID)
                projection.add(MediaStore.Audio.Media.TITLE)
                projection.add(MediaStore.Audio.Media.ARTIST)
                projection.add(MediaStore.Audio.Media.ALBUM)
                projection.add(MediaStore.Audio.Media.DURATION)
                projection.add(MediaStore.Audio.Media.DATE_ADDED)
                projection.add(MediaStore.Audio.Media.DATE_MODIFIED)
                projection.add(MediaStore.Audio.Media.SIZE)
                projection.add(MediaStore.Audio.Media.MIME_TYPE)
                projection.add(MediaStore.Audio.Media.DISPLAY_NAME)
                projection.add(MediaStore.Audio.Media.YEAR)
                if (Build.VERSION.SDK_INT >= 29) {
                    projection.add(MediaStore.Audio.Media.RELATIVE_PATH)
                } else {
                    @Suppress("DEPRECATION")
                    projection.add(MediaStore.Audio.Media.DATA)
                }
                if (Build.VERSION.SDK_INT >= 30) {
                    projection.add(MediaStore.Audio.Media.BITRATE)
                    projection.add(MediaStore.Audio.Media.GENRE)
                }

                val selection =
                    "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0"
                val sort = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

                val cursor = contentResolver.query(
                    media,
                    projection.toTypedArray(),
                    selection,
                    null,
                    sort
                )
                cursor?.use { c ->
                    val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                    val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                    val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                    val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                    val iDuration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                    val iAdded = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                    val iModified = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                    val iSize = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                    val iMime = c.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                    val iName = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                    val iYear = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
                    val iPath = if (Build.VERSION.SDK_INT >= 29) {
                        c.getColumnIndexOrThrow(MediaStore.Audio.Media.RELATIVE_PATH)
                    } else {
                        @Suppress("DEPRECATION")
                        c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    }
                    val iBitrate = if (Build.VERSION.SDK_INT >= 30) {
                        c.getColumnIndex(MediaStore.Audio.Media.BITRATE)
                    } else {
                        -1
                    }
                    val iGenre = if (Build.VERSION.SDK_INT >= 30) {
                        c.getColumnIndex(MediaStore.Audio.Media.GENRE)
                    } else {
                        -1
                    }

                    while (c.moveToNext()) {
                        val id = c.getLong(iId)
                        val row = HashMap<String, Any?>()
                        row["id"] = id.toString()
                        row["uri"] = ContentUris.withAppendedId(media, id).toString()
                        val title = c.getString(iTitle)
                        val displayName = c.getString(iName)
                        row["title"] = if (title.isNullOrBlank()) (displayName ?: "Unknown") else title
                        val artist = c.getString(iArtist)
                        row["artist"] =
                            if (artist.isNullOrBlank() || artist == "<unknown>") "Unknown Artist" else artist
                        val album = c.getString(iAlbum)
                        row["album"] = if (album.isNullOrBlank()) "Unknown Album" else album
                        row["durationMs"] = c.getLong(iDuration)
                        row["dateAddedSec"] = c.getLong(iAdded)
                        row["dateModifiedSec"] = c.getLong(iModified)
                        row["size"] = c.getLong(iSize)
                        row["mime"] = c.getString(iMime)
                        row["year"] = c.getInt(iYear)
                        val path = c.getString(iPath)
                        row["folder"] = if (path == null) {
                            null
                        } else if (Build.VERSION.SDK_INT >= 29) {
                            path.trimEnd('/')
                        } else {
                            File(path).parentFile?.absolutePath
                        }
                        row["bitrate"] = if (iBitrate >= 0) c.getLong(iBitrate) else 0L
                        row["genre"] = if (iGenre >= 0) c.getString(iGenre) else null
                        list.add(row)
                    }
                }
                runOnUiThread { result.success(list) }
            } catch (e: Exception) {
                runOnUiThread { result.error("scan_failed", e.message, null) }
            }
        }
    }

    // ---------------------------------------------------------------- external synced lyrics (.lrc)

    private fun savedLyricsTreeUri(): Uri? = try {
        getSharedPreferences("external_lyrics", MODE_PRIVATE).getString("tree_uri", null)?.let(Uri::parse)
    } catch (_: Throwable) { null }

    private fun lyricsFolderLabel(uri: Uri): String {
        val id = try { DocumentsContract.getTreeDocumentId(uri) } catch (_: Throwable) { "" }
        val path = id.substringAfter(':', id).trim('/')
        return if (path.isBlank()) "Selected folder" else path
    }

    private fun savedLyricsFolderLabel(): String? = savedLyricsTreeUri()?.let { lyricsFolderLabel(it) }

    private data class AudioSidecarLocation(
        val displayName: String,
        val relativeFolder: String,
        val legacyFilePath: String? = null
    )

    private fun readExternalLyrics(id: String, result: MethodChannel.Result) {
        coverExecutor.execute {
            val text = try { findExternalLyrics(id) } catch (_: Throwable) { null }
            runOnUiThread { result.success(text) }
        }
    }

    private fun findExternalLyrics(id: String): String? {
        val mediaUri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id.toLong())
        val projection = if (Build.VERSION.SDK_INT >= 29) {
            arrayOf(MediaStore.Audio.Media.DISPLAY_NAME, MediaStore.Audio.Media.RELATIVE_PATH)
        } else {
            @Suppress("DEPRECATION")
            arrayOf(MediaStore.Audio.Media.DISPLAY_NAME, MediaStore.Audio.Media.DATA)
        }
        val location = contentResolver.query(mediaUri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val displayName = cursor.getString(0) ?: return@use null
            val pathValue = cursor.getString(1) ?: ""
            if (Build.VERSION.SDK_INT >= 29) {
                AudioSidecarLocation(displayName, pathValue.trim('/'))
            } else {
                @Suppress("DEPRECATION")
                val audioFile = File(pathValue)
                val audioFolder = audioFile.parentFile?.absolutePath.orEmpty()
                val storageRoot = Environment.getExternalStorageDirectory().absolutePath.trimEnd('/')
                val relativeFolder = if (audioFolder.equals(storageRoot, ignoreCase = true)) {
                    ""
                } else if (audioFolder.startsWith("$storageRoot/", ignoreCase = true)) {
                    audioFolder.substring(storageRoot.length + 1)
                } else {
                    audioFolder
                }
                AudioSidecarLocation(displayName, relativeFolder.trim('/'), pathValue)
            }
        } ?: return null
        val baseName = location.displayName.substringBeforeLast('.', location.displayName)
        if (baseName.isBlank()) return null
        val lrcName = "$baseName.lrc"

        // On older Android versions, READ_EXTERNAL_STORAGE permits direct access to
        // the sibling file. Prefer this fast path when available.
        location.legacyFilePath?.let { audioPath ->
            val sibling = File(audioPath).parentFile?.let { findCaseInsensitiveFile(it, lrcName) }
            readUtf8File(sibling)?.let { return it }
        }

        // Best-effort MediaStore.Files lookup. Some recent Android versions do not
        // expose non-media sidecars through this collection, so the SAF grant below
        // remains the reliable path on scoped-storage devices.
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                val files = MediaStore.Files.getContentUri("external")
                val projectionFiles = arrayOf(MediaStore.Files.FileColumns._ID)
                val selection = "LOWER(${MediaStore.MediaColumns.DISPLAY_NAME}) = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
                val args = arrayOf(lrcName.lowercase(Locale.ROOT), location.relativeFolder.trimEnd('/') + "/")
                val fileUri = contentResolver.query(files, projectionFiles, selection, args, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        ContentUris.withAppendedId(files, cursor.getLong(0))
                    } else null
                }
                if (fileUri != null) {
                    contentResolver.openInputStream(fileUri)?.use { readUtf8Stream(it) }?.let { return it }
                }
            } catch (_: Throwable) {
                // Continue with the user-granted tree URI.
            }
        }

        return readLrcFromGrantedTree(location.relativeFolder, lrcName)
    }

    private fun readLrcFromGrantedTree(songRelativeFolder: String, lrcName: String): String? {
        val treeUri = savedLyricsTreeUri() ?: return null
        val rootDocumentId = try { DocumentsContract.getTreeDocumentId(treeUri) } catch (_: Throwable) { return null }
        val rootPath = rootDocumentId.substringAfter(':', "").trim('/')
        val songPath = songRelativeFolder.trim('/')
        val remainder = when {
            rootPath.isEmpty() -> songPath
            songPath.equals(rootPath, ignoreCase = true) -> ""
            songPath.startsWith("$rootPath/", ignoreCase = true) -> songPath.substring(rootPath.length + 1)
            else -> return null // The selected tree does not contain this song's folder.
        }

        var currentDocumentId = rootDocumentId
        for (segment in remainder.split('/').filter { it.isNotBlank() }) {
            currentDocumentId = findChildDocumentId(treeUri, currentDocumentId, segment, directory = true)
                ?: return null
        }
        val lrcDocumentId = findChildDocumentId(treeUri, currentDocumentId, lrcName, directory = false)
            ?: return null
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, lrcDocumentId)
        return try { contentResolver.openInputStream(documentUri)?.use { readUtf8Stream(it) } }
        catch (_: Throwable) { null }
    }

    private fun findChildDocumentId(
        treeUri: Uri,
        parentDocumentId: String,
        wantedName: String,
        directory: Boolean
    ): String? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        return contentResolver.query(childrenUri, columns, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                val name = cursor.getString(nameColumn) ?: continue
                if (!name.equals(wantedName, ignoreCase = true)) continue
                val mime = cursor.getString(mimeColumn)
                val isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR
                if (isDirectory == directory) return@use cursor.getString(idColumn)
            }
            null
        }
    }

    private fun findCaseInsensitiveFile(directory: File, wantedName: String): File? = try {
        directory.listFiles()?.firstOrNull { it.isFile && it.name.equals(wantedName, ignoreCase = true) }
    } catch (_: Throwable) { null }

    private fun readUtf8File(file: File?): String? = try {
        if (file == null || !file.isFile || file.length() > 2L * 1024L * 1024L) null
        else file.inputStream().use { readUtf8Stream(it) }
    } catch (_: Throwable) { null }

    private fun readUtf8Stream(input: InputStream): String? {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count <= 0) break
            total += count
            if (total > 2 * 1024 * 1024) return null
            output.write(buffer, 0, count)
        }
        return String(output.toByteArray(), Charsets.UTF_8).removePrefix("\uFEFF")
    }

    // ---------------------------------------------------------------- covers

    private fun loadCover(id: String, size: Int, result: MethodChannel.Result) {
        coverExecutor.execute {
            var outPath: String? = null
            try {
                val dir = File(cacheDir, "covers")
                dir.mkdirs()
                val out = File(dir, "$id-$size.jpg")
                if (out.exists() && out.length() > 0) {
                    outPath = out.absolutePath
                } else {
                    val uri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id.toLong()
                    )
                    var bmp: Bitmap? = null
                    if (Build.VERSION.SDK_INT >= 29) {
                        try {
                            bmp = contentResolver.loadThumbnail(uri, Size(size, size), null)
                        } catch (e: Exception) {
                            bmp = null
                        }
                    }
                    if (bmp == null) {
                        try {
                            val retriever = MediaMetadataRetriever()
                            retriever.setDataSource(this, uri)
                            val data = retriever.embeddedPicture
                            retriever.release()
                            if (data != null) {
                                bmp = BitmapFactory.decodeByteArray(data, 0, data.size)
                            }
                        } catch (e: Exception) {
                            bmp = null
                        }
                    }
                    val finalBmp = bmp
                    if (finalBmp != null) {
                        FileOutputStream(out).use { stream ->
                            finalBmp.compress(Bitmap.CompressFormat.JPEG, 92, stream)
                        }
                        outPath = out.absolutePath
                    }
                }
            } catch (e: Exception) {
                outPath = null
            }
            val reply = outPath
            runOnUiThread { result.success(reply) }
        }
    }

    private fun readHead(id: String, maxBytes: Int, result: MethodChannel.Result) {
        coverExecutor.execute {
            var data: ByteArray? = null
            try {
                val uri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    id.toLong()
                )
                val stream = contentResolver.openInputStream(uri)
                if (stream != null) {
                    stream.use { input ->
                        val buffer = ByteArray(maxBytes)
                        var total = 0
                        while (total < maxBytes) {
                            val n = input.read(buffer, total, maxBytes - total)
                            if (n <= 0) break
                            total += n
                        }
                        data = buffer.copyOf(total)
                    }
                }
            } catch (e: Exception) {
                data = null
            }
            val reply = data
            runOnUiThread { result.success(reply) }
        }
    }

    // ---------------------------------------------------------------- loudness analysis fallback

    /**
     * Decodes this MediaStore item with Android's codec and estimates an EBU-R128-style
     * integrated loudness. This is intentionally a scan-time fallback only; it never edits
     * the user's file. Null means the scan was cooperatively cancelled.
     */
    private fun analyzeLoudness(id: String, requestedTargetLufs: Double, result: MethodChannel.Result) {
        val token = loudnessScanGeneration
        val targetLufs = requestedTargetLufs.coerceIn(-24.0, -9.0)
        loudnessScanExecutor.execute {
            val report: Map<String, Any?>? = try {
                if (!isCurrentLoudnessScan(token)) null
                else decodeAndMeasureLoudness(id, targetLufs, token)
            } catch (_: Throwable) {
                if (isCurrentLoudnessScan(token)) mapOf("success" to false) else null
            }
            runOnUiThread {
                try { result.success(report) } catch (_: Throwable) {}
            }
        }
    }

    private fun isCurrentLoudnessScan(token: Long): Boolean = token == loudnessScanGeneration

    private fun decodeAndMeasureLoudness(
        id: String,
        targetLufs: Double,
        token: Long
    ): Map<String, Any?>? {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id.toLong())
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        var started = false
        try {
            extractor.setDataSource(this, uri, null)
            var audioTrack = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrack = i
                    inputFormat = fmt
                    break
                }
            }
            val selectedFormat = inputFormat ?: return mapOf("success" to false)
            if (audioTrack < 0 || !isCurrentLoudnessScan(token)) return null
            val mime = selectedFormat.getString(MediaFormat.KEY_MIME) ?: return mapOf("success" to false)
            extractor.selectTrack(audioTrack)
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(selectedFormat, null, null, 0)
            codec.start()
            started = true

            var sampleRate = selectedFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = selectedFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT
            var analyzer: DecodedLoudnessAnalyzer? = null
            var inputDone = false
            var outputDone = false
            val info = MediaCodec.BufferInfo()

            while (!outputDone) {
                if (!isCurrentLoudnessScan(token)) return null
                if (!inputDone) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputIndex)
                        if (inputBuffer == null) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0L, 0)
                        } else {
                            inputBuffer.clear()
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(
                                    inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                                )
                                inputDone = true
                            } else {
                                val pts = extractor.sampleTime.coerceAtLeast(0L)
                                codec.queueInputBuffer(inputIndex, 0, sampleSize, pts, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outputIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outputIndex >= 0 -> {
                        val outputBuffer = codec.getOutputBuffer(outputIndex)
                        if (outputBuffer != null && info.size > 0) {
                            val outputFormat = codec.outputFormat
                            sampleRate = outputFormat.integerOr(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                            channels = outputFormat.integerOr(MediaFormat.KEY_CHANNEL_COUNT, channels)
                            pcmEncoding = outputFormat.integerOr("pcm-encoding", pcmEncoding)
                            if (channels <= 0 || sampleRate <= 0) {
                                codec.releaseOutputBuffer(outputIndex, false)
                                return mapOf("success" to false)
                            }
                            if (analyzer == null) {
                                analyzer = DecodedLoudnessAnalyzer(sampleRate, channels)
                            }
                            val pcm = outputBuffer.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                            pcm.position(info.offset)
                            pcm.limit(info.offset + info.size)
                            analyzer.accept(pcm.slice().order(ByteOrder.LITTLE_ENDIAN), pcmEncoding)
                        }
                        if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                    outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = codec.outputFormat
                        sampleRate = format.integerOr(MediaFormat.KEY_SAMPLE_RATE, sampleRate)
                        channels = format.integerOr(MediaFormat.KEY_CHANNEL_COUNT, channels)
                        pcmEncoding = format.integerOr("pcm-encoding", pcmEncoding)
                        if (analyzer == null && sampleRate > 0 && channels > 0) {
                            analyzer = DecodedLoudnessAnalyzer(sampleRate, channels)
                        }
                    }
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> Unit
                }
            }
            if (!isCurrentLoudnessScan(token)) return null
            val measured = analyzer?.measure(targetLufs) ?: return mapOf("success" to false)
            return mapOf(
                "success" to true,
                "gainDb" to measured.gainDb,
                "peak" to measured.peak,
                "integratedLufs" to measured.integratedLufs
            )
        } finally {
            if (started) try { decoder?.stop() } catch (_: Throwable) {}
            try { decoder?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    private fun MediaFormat.integerOr(key: String, fallback: Int): Int = try {
        getInteger(key)
    } catch (_: Throwable) { fallback }

    private data class LoudnessMeasurement(val gainDb: Double, val peak: Double, val integratedLufs: Double)

    /**
     * Streaming K-weighted energy accumulator. Uses the published 44.1/48 kHz
     * BS.1770 biquad coefficients, 400 ms windows at 100 ms hops, an absolute -70 LUFS
     * gate and a -10 LU relative gate. Sample peak is retained for the existing peak guard.
     */
    private class DecodedLoudnessAnalyzer(private val sampleRate: Int, private val channels: Int) {
        private data class Biquad(
            private val b0: Double, private val b1: Double, private val b2: Double,
            private val a1: Double, private val a2: Double
        ) {
            private var x1 = 0.0
            private var x2 = 0.0
            private var y1 = 0.0
            private var y2 = 0.0
            fun process(x: Double): Double {
                val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x
                y2 = y1; y1 = y
                return if (y.isFinite()) y else 0.0
            }
        }

        private val shelf: Array<Biquad>
        private val highPass: Array<Biquad>
        private val chunkFramesTarget = maxOf(1, sampleRate / 10)
        private var chunkFrames = 0
        private var chunkEnergy = 0.0
        private var totalFrames = 0L
        private var totalEnergy = 0.0
        private var samplePeak = 0.0
        private val lastChunks = ArrayDeque<Double>()
        private val blockEnergies = ArrayList<Double>()

        init {
            val use48 = sampleRate >= 46_000
            val shelfB0 = if (use48) 1.53512485958697 else 1.53084123005035
            val shelfB1 = if (use48) -2.69169618940638 else -2.65097999515473
            val shelfB2 = if (use48) 1.19839281085285 else 1.16907907992107
            val shelfA1 = if (use48) -1.69065929318241 else -1.66365511325602
            val shelfA2 = if (use48) 0.73248077421585 else 0.712595428073225
            val hpA1 = if (use48) -1.99004745483398 else -1.98916967362980
            val hpA2 = if (use48) 0.99007225036621 else 0.989199035787039
            shelf = Array(channels) { Biquad(shelfB0, shelfB1, shelfB2, shelfA1, shelfA2) }
            highPass = Array(channels) { Biquad(1.0, -2.0, 1.0, hpA1, hpA2) }
        }

        fun accept(buffer: java.nio.ByteBuffer, pcmEncoding: Int) {
            val bytesPerSample = if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
            val frameSize = bytesPerSample * channels
            while (buffer.remaining() >= frameSize) {
                var frameEnergy = 0.0
                for (channel in 0 until channels) {
                    val raw = if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
                        buffer.float.toDouble().coerceIn(-1.0, 1.0)
                    } else {
                        buffer.short.toDouble() / 32768.0
                    }
                    samplePeak = maxOf(samplePeak, kotlin.math.abs(raw))
                    val weighted = highPass[channel].process(shelf[channel].process(raw))
                    frameEnergy += weighted * weighted
                }
                totalEnergy += frameEnergy
                totalFrames++
                chunkEnergy += frameEnergy
                chunkFrames++
                if (chunkFrames >= chunkFramesTarget) {
                    val meanEnergy = chunkEnergy / chunkFrames
                    lastChunks.addLast(meanEnergy)
                    while (lastChunks.size > 4) lastChunks.removeFirst()
                    if (lastChunks.size == 4) blockEnergies.add(lastChunks.sum() / 4.0)
                    chunkFrames = 0
                    chunkEnergy = 0.0
                }
            }
        }

        fun measure(targetLufs: Double): LoudnessMeasurement? {
            if (totalFrames <= 0 || samplePeak <= 0.0 || !totalEnergy.isFinite() || totalEnergy <= 0.0) return null
            val absoluteGateEnergy = 10.0.pow10((-70.0 + 0.691) / 10.0)
            val absoluteGated = if (blockEnergies.isEmpty()) {
                listOf(totalEnergy / totalFrames)
            } else {
                blockEnergies.filter { it >= absoluteGateEnergy }
            }
            if (absoluteGated.isEmpty()) return null
            val preliminaryEnergy = absoluteGated.average().coerceAtLeast(1e-12)
            val preliminaryLufs = -0.691 + 10.0 * log10(preliminaryEnergy)
            val relativeGateEnergy = 10.0.pow10((preliminaryLufs - 10.0 + 0.691) / 10.0)
            val gated = absoluteGated.filter { it >= maxOf(absoluteGateEnergy, relativeGateEnergy) }
            val finalEnergy = (if (gated.isNotEmpty()) gated.average() else preliminaryEnergy).coerceAtLeast(1e-12)
            val lufs = -0.691 + 10.0 * log10(finalEnergy)
            if (!lufs.isFinite()) return null
            return LoudnessMeasurement(
                gainDb = (targetLufs - lufs).coerceIn(-36.0, 36.0),
                peak = samplePeak.coerceIn(0.0, 1.0),
                integratedLufs = lufs
            )
        }

        private fun Double.pow10(exponent: Double): Double = this.pow(exponent)
    }

    // ---------------------------------------------------------------- ReplayGain tag reader

    private fun readReplayGain(id: String, result: MethodChannel.Result) {
        coverExecutor.execute {
            val tags = try {
                readReplayGainTags(id)
            } catch (_: Throwable) {
                emptyMap<String, Any?>()
            }
            runOnUiThread { result.success(tags) }
        }
    }

    /** Reads only metadata-sized windows; it never scans/decodes the audio payload. */
    private fun readReplayGainTags(id: String): Map<String, Any?> {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id.toLong())
        val pfd = contentResolver.openFileDescriptor(uri, "r") ?: return emptyMap()
        val fileSize = pfd.statSize
        val maxId3Head = 4 * 1024 * 1024
        val ordinaryHead = 512 * 1024
        val tailLimit = 2 * 1024 * 1024
        var head = ByteArray(0)
        var tail = ByteArray(0)
        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { input ->
            val prefix = readLimited(input, 10)
            val hasId3Header = prefix.size >= 10 && prefix[0] == 0x49.toByte() &&
                prefix[1] == 0x44.toByte() && prefix[2] == 0x33.toByte()
            val wantedHead = if (hasId3Header) {
                minOf(maxId3Head, maxOf(10, id3SyncSafe(prefix, 6) + 10))
            } else ordinaryHead
            try {
                input.channel.position(0L)
                head = readLimited(input, wantedHead)
            } catch (_: Throwable) {
                // For non-seekable providers the prefix is still useful for ID3-less tags.
                head = prefix
            }
            if (fileSize > wantedHead.toLong()) {
                try {
                    val start = (fileSize - tailLimit).coerceAtLeast(0L)
                    input.channel.position(start)
                    tail = readLimited(input, tailLimit)
                } catch (_: Throwable) {
                    // Some content providers expose a non-seekable descriptor. ID3 and
                    // Vorbis comments are at the start, so head-tag support still works.
                }
            }
        }

        val parsed = LinkedHashMap<String, Double>()
        parsed.putAll(parseId3ReplayGain(head))
        parsed.putAll(parseReplayGainText(head, parsed.keys))
        parsed.putAll(parseReplayGainText(tail, parsed.keys))
        parseMp4FreeformGain(head, parsed)
        parseMp4FreeformGain(tail, parsed)

        // Use track gain when present. Dart chooses album gain only when track gain is absent.
        return mapOf(
            "trackGainDb" to parsed["replaygain_track_gain"],
            "albumGainDb" to parsed["replaygain_album_gain"],
            "trackPeak" to parsed["replaygain_track_peak"],
            "albumPeak" to parsed["replaygain_album_peak"]
        )
    }

    private fun readLimited(input: InputStream, limit: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream(minOf(limit, 65536))
        val buffer = ByteArray(16384)
        var total = 0
        while (total < limit) {
            val n = input.read(buffer, 0, minOf(buffer.size, limit - total))
            if (n <= 0) break
            out.write(buffer, 0, n)
            total += n
        }
        return out.toByteArray()
    }

    private fun id3SyncSafe(data: ByteArray, offset: Int): Int {
        if (offset + 3 >= data.size) return 0
        return ((data[offset].toInt() and 0x7f) shl 21) or
            ((data[offset + 1].toInt() and 0x7f) shl 14) or
            ((data[offset + 2].toInt() and 0x7f) shl 7) or
            (data[offset + 3].toInt() and 0x7f)
    }

    private fun id3FrameSize(data: ByteArray, offset: Int, version: Int): Int {
        if (offset + 7 >= data.size) return 0
        if (version == 4) return id3SyncSafe(data, offset + 4)
        return ((data[offset + 4].toInt() and 0xff) shl 24) or
            ((data[offset + 5].toInt() and 0xff) shl 16) or
            ((data[offset + 6].toInt() and 0xff) shl 8) or
            (data[offset + 7].toInt() and 0xff)
    }

    private fun decodeId3Text(bytes: ByteArray, encoding: Int): String {
        val charset = when (encoding) {
            0 -> Charsets.ISO_8859_1
            1 -> Charsets.UTF_16
            2 -> Charsets.UTF_16BE
            else -> Charsets.UTF_8
        }
        return String(bytes, charset).trim('\u0000', ' ', '\t', '\r', '\n')
    }

    private fun parseId3ReplayGain(data: ByteArray): Map<String, Double> {
        val found = LinkedHashMap<String, Double>()
        if (data.size < 10 || data[0] != 0x49.toByte() || data[1] != 0x44.toByte() || data[2] != 0x33.toByte()) return found
        val version = data[3].toInt() and 0xff
        if (version !in 3..4) return found
        val tagEnd = minOf(data.size, id3SyncSafe(data, 6) + 10)
        var offset = 10
        while (offset + 10 <= tagEnd) {
            val frameId = String(data, offset, 4, Charsets.ISO_8859_1)
            if (frameId.all { it == '\u0000' }) break
            if (!frameId.matches(Regex("^[A-Z0-9]{4}$"))) break
            val frameSize = id3FrameSize(data, offset, version)
            if (frameSize <= 0 || offset + 10 + frameSize > tagEnd) break
            if (frameId == "TXXX") {
                val bodyStart = offset + 10
                val bodyEnd = bodyStart + frameSize
                if (bodyStart < bodyEnd) {
                    val encoding = data[bodyStart].toInt() and 0xff
                    val payloadStart = bodyStart + 1
                    var separator = -1
                    var valueStart = -1
                    if (encoding == 1 || encoding == 2) {
                        var j = payloadStart
                        while (j + 1 < bodyEnd) {
                            if (data[j] == 0.toByte() && data[j + 1] == 0.toByte()) {
                                separator = j
                                valueStart = j + 2
                                break
                            }
                            j += 2
                        }
                    } else {
                        var j = payloadStart
                        while (j < bodyEnd) {
                            if (data[j] == 0.toByte()) {
                                separator = j
                                valueStart = j + 1
                                break
                            }
                            j++
                        }
                    }
                    if (separator >= payloadStart && valueStart >= 0) {
                        val description = decodeId3Text(data.copyOfRange(payloadStart, separator), encoding)
                            .lowercase(Locale.ROOT).trim()
                        val value = decodeId3Text(data.copyOfRange(valueStart, bodyEnd), encoding)
                        val key = description.substringAfterLast(':')
                        replayGainKeyValue(key, value)?.let { (k, v) -> found[k] = v }
                    }
                }
            }
            offset += 10 + frameSize
        }
        return found
    }

    private fun replayGainKeyValue(name: String, rawValue: String): Pair<String, Double>? {
        val key = name.trim().lowercase(Locale.ROOT).replace('-', '_').replace(' ', '_')
        if (key !in setOf("replaygain_track_gain", "replaygain_track_peak", "replaygain_album_gain", "replaygain_album_peak")) return null
        val match = Regex("[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)").find(rawValue) ?: return null
        val number = match.value.toDoubleOrNull() ?: return null
        if (!number.isFinite()) return null
        if (key.endsWith("_peak") && number < 0.0) return null
        if (key.endsWith("_gain") && (number < -60.0 || number > 60.0)) return null
        if (key.endsWith("_peak") && number > 100.0) return null
        return key to number
    }

    private fun parseReplayGainText(data: ByteArray, alreadyFound: Set<String>): Map<String, Double> {
        val text = String(data, Charsets.ISO_8859_1)
        val found = LinkedHashMap<String, Double>()
        val keys = listOf(
            "replaygain_track_gain", "replaygain_track_peak", "replaygain_album_gain", "replaygain_album_peak"
        )
        for (key in keys) {
            if (key in alreadyFound) continue
            val pattern = Regex(
                Regex.escape(key) + "(?:[\\u0000\\s=:]{1,24})([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))\\s*(?:dB)?",
                RegexOption.IGNORE_CASE
            )
            val match = pattern.find(text) ?: continue
            replayGainKeyValue(key, match.groupValues[1])?.let { (k, v) -> found[k] = v }
        }
        return found
    }

    /** Supports MP4/iTunes freeform ReplayGain atoms (----:com.apple.iTunes:replaygain_*). */
    private fun parseMp4FreeformGain(data: ByteArray, found: MutableMap<String, Double>) {
        val text = String(data, Charsets.ISO_8859_1)
        for (key in listOf("replaygain_track_gain", "replaygain_track_peak", "replaygain_album_gain", "replaygain_album_peak")) {
            if (key in found) continue
            var from = 0
            while (from < text.length) {
                val keyIndex = text.indexOf(key, from, ignoreCase = true)
                if (keyIndex < 0) break
                val dataIndex = text.indexOf("data", keyIndex + key.length, ignoreCase = true)
                if (dataIndex < 0 || dataIndex + 12 >= text.length) break
                val end = minOf(text.length, dataIndex + 80)
                val valueText = text.substring(dataIndex + 12, end)
                replayGainKeyValue(key, valueText)?.let { (k, v) -> found.putIfAbsent(k, v) }
                from = keyIndex + key.length
                if (key in found) break
            }
        }
    }


    override fun onDestroy() {
        // Do not release native effects here. The media foreground service can keep
        // the audio session alive after this Activity is removed from Recents.
        // AudioEffectManager owns the effects at process/session scope instead.
        try { fxExecutor.shutdown() } catch (_: Throwable) {}
        super.onDestroy()
    }
}
