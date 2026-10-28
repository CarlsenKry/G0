package com.aether.music

import android.app.Application
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Registers a screen-state receiver for as long as the app process lives (the media
 * foreground service keeps it alive while music is playing), monitors external lyrics,
 * and shows the custom lock screen after the display turns on while keyguard is locked.
 */
class KryptonApplication : Application() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    // Never start an Activity as the display is turning off; doing so
                    // can fight the user's configured Android screen-off timeout.
                    LockScreenActivity.dismissIfShowing()
                    LockLauncher.cancelFallbackNotification(context.applicationContext)
                }
                Intent.ACTION_SCREEN_ON ->
                    LockLauncher.launchAfterScreenOn(context.applicationContext)
                Intent.ACTION_USER_PRESENT -> LockScreenActivity.dismissIfShowing()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        LyricsFileMonitor.start(this)
        val filter = IntentFilter()
        filter.addAction(Intent.ACTION_SCREEN_OFF)
        filter.addAction(Intent.ACTION_SCREEN_ON)
        filter.addAction(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
    }
}

object LockLauncher {
    const val NOTIFICATION_ID = 4712
    private const val CHANNEL_ID = "com.aether.music.channel.lockscreen"

    fun buildIntent(ctx: Context, preview: Boolean): Intent {
        val intent = Intent(ctx, LockScreenActivity::class.java)
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_NO_ANIMATION or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        )
        intent.putExtra(LockScreenActivity.EXTRA_PREVIEW, preview)
        return intent
    }

    private fun shouldShow(): Boolean {
        if (!LockState.enabled || !LockState.hasTrack) return false
        if (LockState.flag("onlyWhilePlaying", true) && !LockState.playing) return false
        return true
    }

    fun launchAfterScreenOn(ctx: Context) {
        // Wait for keyguard state to settle after ACTION_SCREEN_ON; retry once for
        // devices that report the locked state slightly later.
        val app = ctx.applicationContext
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed({ launchIfNeeded(app, true) }, 350L)
        handler.postDelayed({ launchIfNeeded(app, true) }, 900L)
    }

    fun cancelFallbackNotification(ctx: Context) {
        try {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(NOTIFICATION_ID)
        } catch (_: Throwable) {}
    }

    fun launchIfNeeded(ctx: Context, requireLocked: Boolean) {
        if (!shouldShow() || LockScreenActivity.isShowing) return
        if (requireLocked) {
            val km = ctx.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (!km.isKeyguardLocked) return
        }
        val intent = buildIntent(ctx, false)
        try {
            ctx.startActivity(intent)
        } catch (_: Throwable) {
        }
        // Android 10+ may silently block activity starts from the background unless
        // "Display over other apps" is granted. If the activity did not come up, fall
        // back to a full-screen-intent notification, which Android allows while locked.
        if (Build.VERSION.SDK_INT >= 29) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (!LockScreenActivity.isShowing && shouldShow()) {
                    postFullScreenFallback(ctx, intent)
                }
            }, 900)
        }
    }

    private fun postFullScreenFallback(ctx: Context, intent: Intent) {
        try {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lock screen player",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.setSound(null, null)
            channel.enableVibration(false)
            channel.setShowBadge(false)
            nm.createNotificationChannel(channel)
            val pi = PendingIntent.getActivity(
                ctx,
                7,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val n = Notification.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Krypton m.Player")
                .setContentText(LockState.title)
                .setCategory(Notification.CATEGORY_TRANSPORT)
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setFullScreenIntent(pi, true)
                .setAutoCancel(true)
                .setTimeoutAfter(5000)
                .build()
            nm.notify(NOTIFICATION_ID, n)
        } catch (_: Throwable) {
        }
    }
}
