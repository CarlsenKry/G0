package com.aether.music

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore

/**
 * Watches the selected SAF lyrics tree and MediaStore for sidecar changes.
 * A monotonically increasing token is persisted so Flutter can notice updates
 * even if its UI isolate was temporarily paused while a file was added.
 */
object LyricsFileMonitor {
    private const val PREFS = "external_lyrics"
    private const val TREE_URI_KEY = "tree_uri"
    private const val CHANGE_TOKEN_KEY = "change_token"

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var appContext: Context? = null
    @Volatile private var mediaObserverRegistered = false
    private var observedTreeUri: Uri? = null
    private var treeObserver: ContentObserver? = null
    private var mediaObserver: ContentObserver? = null

    private val markChangedRunnable = Runnable {
        val context = appContext ?: return@Runnable
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        synchronized(this) {
            val next = prefs.getLong(CHANGE_TOKEN_KEY, 0L) + 1L
            prefs.edit().putLong(CHANGE_TOKEN_KEY, next).apply()
        }
    }

    @Synchronized
    fun start(context: Context) {
        val app = context.applicationContext
        appContext = app
        if (!mediaObserverRegistered) {
            val filesUri = MediaStore.Files.getContentUri("external")
            mediaObserver = object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    markChanged()
                }

                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    if (isPossibleLyricsChange(app, uri, filesUri)) markChanged()
                }
            }
            try {
                app.contentResolver.registerContentObserver(filesUri, true, mediaObserver!!)
                mediaObserverRegistered = true
            } catch (_: Throwable) {
                mediaObserver = null
            }
        }
        val tree = try {
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(TREE_URI_KEY, null)?.let(Uri::parse)
        } catch (_: Throwable) { null }
        setTreeUri(app, tree)
    }

    @Synchronized
    fun setTreeUri(context: Context, uri: Uri?) {
        val app = context.applicationContext
        appContext = app
        if (observedTreeUri == uri && treeObserver != null) return
        try { treeObserver?.let { app.contentResolver.unregisterContentObserver(it) } } catch (_: Throwable) {}
        treeObserver = null
        observedTreeUri = uri
        if (uri != null) {
            val observer = object : ContentObserver(mainHandler) {
                override fun onChange(selfChange: Boolean) {
                    markChanged()
                }

                override fun onChange(selfChange: Boolean, changedUri: Uri?) {
                    // SAF providers differ in how they report descendant changes. Any
                    // notification under the granted tree invalidates lyrics caches.
                    markChanged()
                }
            }
            try {
                app.contentResolver.registerContentObserver(uri, true, observer)
                treeObserver = observer
            } catch (_: Throwable) {
                treeObserver = null
            }
        }
        // Force one refresh after a new tree has been selected.
        markChanged()
    }

    fun changeToken(context: Context): Long = try {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(CHANGE_TOKEN_KEY, 0L)
    } catch (_: Throwable) { 0L }

    private fun markChanged() {
        mainHandler.removeCallbacks(markChangedRunnable)
        mainHandler.postDelayed(markChangedRunnable, 350L)
    }

    private fun isPossibleLyricsChange(context: Context, uri: Uri?, collectionUri: Uri): Boolean {
        if (uri == null || uri == collectionUri) return true
        val name = try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Throwable) { null }
        // A collection-level notification can have no resolvable name; in that case
        // refresh defensively. Concrete unrelated files are ignored.
        return name == null || name.endsWith(".lrc", ignoreCase = true)
    }
}
