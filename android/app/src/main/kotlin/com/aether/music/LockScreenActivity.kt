package com.aether.music

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.text.format.DateFormat
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import java.lang.ref.WeakReference
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/**
 * Custom "Screenlock KRY player": a dark slide-to-unlock music screen shown over the
 * keyguard. It is drawn with plain Android views (fast to start, no Flutter surface
 * needed while the device is locked) and driven by [LockState], which the Dart player
 * keeps up to date. Which parts are visible is decided by the options the user toggles
 * in Settings -> Screenlock KRY player.
 */
@Suppress("DEPRECATION")
class LockScreenActivity : Activity() {

    companion object {
        const val EXTRA_PREVIEW = "preview"

        @Volatile
        var isShowing = false

        private var instance: WeakReference<LockScreenActivity>? = null

        fun dismissIfShowing() {
            val a = instance?.get() ?: return
            if (!a.previewMode) a.finishAndRemoveTask()
        }
    }

    internal var previewMode = false

    private val ui = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private lateinit var root: FrameLayout
    private lateinit var bgImage: ImageView
    private lateinit var dimView: View
    private lateinit var content: LinearLayout
    private lateinit var center: FrameLayout
    private lateinit var slide: SlideToUnlockView

    private var clockText: TextView? = null
    private var dateText: TextView? = null
    private var coverFrame: FrameLayout? = null
    private var coverImage: ImageView? = null
    private var coverLetter: TextView? = null
    private var lyricsBox: LinearLayout? = null
    private var lyricViews: List<TextView> = emptyList()
    private var queueBox: LinearLayout? = null
    private var queueBody: TextView? = null
    private var titleText: TextView? = null
    private var artistText: TextView? = null
    private var albumText: TextView? = null
    private var seekBar: SeekBar? = null
    private var leftTime: TextView? = null
    private var rightTime: TextView? = null
    private var playButton: ImageView? = null
    private var favButton: ImageView? = null
    private var shuffleButton: ImageView? = null
    private var repeatButton: ImageView? = null
    private var queueButton: ImageView? = null
    private var lyricsButton: ImageView? = null

    private var accent = Color.WHITE
    private var mode = 0 // 0 cover, 1 lyrics, 2 queue
    private var scrubbing = false
    private var lastOptsSignature = ""
    private var loadedCover: String? = "\u0000"
    private var lastClock = ""
    private var lastDate = ""
    private var spin: android.animation.ObjectAnimator? = null

    private val stateListener = Runnable { onStateChanged() }

    private val tick = object : Runnable {
        override fun run() {
            bindTick()
            ui.postDelayed(this, 500)
        }
    }

    // ------------------------------------------------------------------ lifecycle

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        previewMode = intent?.getBooleanExtra(EXTRA_PREVIEW, false) == true

        // This overlay must never keep the display awake. Android's own display
        // timeout should turn the screen off normally, even while this Activity exists.
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.keepScreenOn = false

        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
        if (Build.VERSION.SDK_INT >= 28) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = lp
        }
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
        } else {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }

        isShowing = true
        instance = WeakReference(this)

        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(LockLauncher.NOTIFICATION_ID)
        } catch (_: Throwable) {
        }

        buildUi()
        LockState.listeners.add(stateListener)
        bindAll()
    }

    override fun onResume() {
        super.onResume()
        slide.setAnimating(true)
        ui.removeCallbacks(tick)
        ui.post(tick)
        bindAll()
    }

    override fun onPause() {
        ui.removeCallbacks(tick)
        slide.setAnimating(false)
        super.onPause()
    }

    override fun onDestroy() {
        LockState.listeners.remove(stateListener)
        ui.removeCallbacks(tick)
        spin?.cancel()
        io.shutdownNow()
        isShowing = false
        if (instance?.get() === this) instance = null
        super.onDestroy()
    }

    override fun onBackPressed() {
        // Back must not bypass the lock screen; only the preview can be closed this way.
        if (previewMode) super.onBackPressed()
    }

    // ------------------------------------------------------------------ helpers

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density + 0.5f).toInt()

    private fun optionsSignature(): String = LockState.opts.toString()

    private fun lp(w: Int, h: Int): LinearLayout.LayoutParams = LinearLayout.LayoutParams(w, h)

    private fun fmt(ms: Long): String {
        val t = (if (ms < 0) 0L else ms) / 1000
        val h = (t / 3600).toInt()
        val m = ((t % 3600) / 60).toInt()
        val s = (t % 60).toInt()
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%d:%02d", m, s)
    }

    private fun label(sizeSp: Float, color: Int, bold: Boolean = false): TextView {
        val t = TextView(this)
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        t.setTextColor(color)
        t.includeFontPadding = false
        if (bold) t.typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
        return t
    }

    private fun iconButton(res: Int, sizeDp: Int, paddingDp: Int = 10, onClick: () -> Unit): ImageView {
        val b = ImageView(this)
        b.setImageResource(res)
        b.scaleType = ImageView.ScaleType.CENTER_INSIDE
        b.setPadding(dp(paddingDp), dp(paddingDp), dp(paddingDp), dp(paddingDp))
        b.setColorFilter(Color.WHITE)
        val tv = TypedValue()
        if (theme.resolveAttribute(android.R.attr.selectableItemBackgroundBorderless, tv, true) &&
            tv.resourceId != 0
        ) {
            b.background = getDrawable(tv.resourceId)
        }
        b.setOnClickListener { onClick() }
        b.layoutParams = ViewGroup.LayoutParams(dp(sizeDp), dp(sizeDp))
        return b
    }

    private fun tint(v: ImageView?, color: Int) {
        v?.setColorFilter(color)
    }

    private fun applyInsets() {
        root.setOnApplyWindowInsetsListener { _, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= 30) {
                val b = insets.getInsets(
                    WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
                )
                top = b.top
                bottom = b.bottom
            } else {
                top = insets.systemWindowInsetTop
                bottom = insets.systemWindowInsetBottom
            }
            content.setPadding(dp(20), top + dp(8), dp(20), bottom + dp(22))
            insets
        }
        root.requestApplyInsets()
    }

    // ------------------------------------------------------------------ build

    private fun buildUi() {
        spin?.cancel()
        spin = null
        loadedCover = "\u0000"
        lastClock = ""
        lastDate = ""
        lastOptsSignature = optionsSignature()

        val showAccent = LockState.flag("accentTint", true)
        accent = if (showAccent) LockState.accent else Color.WHITE

        root = FrameLayout(this)
        root.setBackgroundColor(Color.BLACK)

        bgImage = ImageView(this)
        bgImage.scaleType = ImageView.ScaleType.CENTER_CROP
        bgImage.visibility = View.GONE
        root.addView(
            bgImage,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        dimView = View(this)
        val dimAlpha = (LockState.number("dim", 62).coerceIn(0, 100) * 255 / 100)
        dimView.setBackgroundColor(Color.argb(dimAlpha, 0, 0, 0))
        root.addView(
            dimView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        content = LinearLayout(this)
        content.orientation = LinearLayout.VERTICAL
        content.gravity = Gravity.CENTER_HORIZONTAL
        root.addView(
            content,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        buildTopBar()
        buildCenter()
        buildSecondaryControls()
        buildInfoRow()
        buildSeekRow()
        buildControls()
        buildSlider()

        setContentView(root)
        applyInsets()
        applyMode()
    }

    private fun buildTopBar() {
        val bar = FrameLayout(this)

        clockText = null
        dateText = null
        val showClock = LockState.flag("showClock", true)
        val showDate = LockState.flag("showDate", true)
        if (showClock || showDate) {
            val col = LinearLayout(this)
            col.orientation = LinearLayout.VERTICAL
            col.gravity = Gravity.CENTER_HORIZONTAL
            if (showClock) {
                val c = label(52f, Color.WHITE)
                c.typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                clockText = c
                col.addView(c, lp(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
            if (showDate) {
                val d = label(16f, 0xFFC8C8C8.toInt())
                dateText = d
                val dl = lp(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                dl.topMargin = dp(if (showClock) 4 else 0)
                col.addView(d, dl)
            }
            bar.addView(
                col,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER_HORIZONTAL or Gravity.TOP
                )
            )
        }

        queueButton = null
        if (LockState.flag("showQueueButton", true)) {
            val b = iconButton(R.drawable.ic_ls_queue, 46) { setMode(2) }
            b.setColorFilter(0xFFDDDDDD.toInt())
            queueButton = b
            bar.addView(b, FrameLayout.LayoutParams(dp(46), dp(46), Gravity.START or Gravity.TOP))
        }
        lyricsButton = null
        if (LockState.flag("showLyricsButton", true)) {
            val b = iconButton(R.drawable.ic_ls_lyrics, 46) { setMode(1) }
            b.setColorFilter(0xFFDDDDDD.toInt())
            lyricsButton = b
            bar.addView(b, FrameLayout.LayoutParams(dp(46), dp(46), Gravity.END or Gravity.TOP))
        }

        content.addView(bar, lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun buildCenter() {
        center = FrameLayout(this)
        content.addView(center, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        coverFrame = null
        coverImage = null
        coverLetter = null
        if (LockState.flag("showCover", true)) {
            val metrics = resources.displayMetrics
            val pct = LockState.number("coverSize", 72).coerceIn(40, 95)
            val size = min(
                (metrics.widthPixels * pct / 100f).toInt(),
                (metrics.heightPixels * 0.42f).toInt()
            )
            val shape = LockState.text("coverShape", "rounded")
            val frame = FrameLayout(this)
            frame.clipToOutline = true
            frame.outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    when (shape) {
                        "circle" -> outline.setOval(0, 0, view.width, view.height)
                        "square" -> outline.setRect(0, 0, view.width, view.height)
                        else -> outline.setRoundRect(
                            0, 0, view.width, view.height, dp(28).toFloat()
                        )
                    }
                }
            }
            val bg = GradientDrawable()
            bg.setColor(0xFF161616.toInt())
            frame.background = bg

            val letter = label(size / 3.2f / resources.displayMetrics.scaledDensity, 0x55FFFFFF)
            letter.gravity = Gravity.CENTER
            frame.addView(
                letter,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            val img = ImageView(this)
            img.scaleType = ImageView.ScaleType.CENTER_CROP
            frame.addView(
                img,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            )
            frame.elevation = dp(14).toFloat()
            center.addView(frame, FrameLayout.LayoutParams(size, size, Gravity.CENTER))
            coverFrame = frame
            coverImage = img
            coverLetter = letter
        }

        // Lyrics panel: five lines around the current one.
        val lyrics = LinearLayout(this)
        lyrics.orientation = LinearLayout.VERTICAL
        lyrics.gravity = Gravity.CENTER
        lyrics.setPadding(dp(8), dp(8), dp(8), dp(8))
        val lines = ArrayList<TextView>()
        for (i in 0 until 5) {
            val t = label(if (i == 2) 22f else 16f, Color.WHITE, i == 2)
            t.gravity = Gravity.CENTER
            t.maxLines = 3
            t.ellipsize = TextUtils.TruncateAt.END
            val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            l.topMargin = dp(10)
            lyrics.addView(t, l)
            lines.add(t)
        }
        lyricViews = lines
        lyricsBox = lyrics
        center.addView(
            lyrics,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        // Queue panel.
        val queue = LinearLayout(this)
        queue.orientation = LinearLayout.VERTICAL
        queue.gravity = Gravity.CENTER_HORIZONTAL
        queue.setPadding(dp(8), dp(16), dp(8), dp(8))
        val header = label(12f, accent, true)
        header.text = "UP NEXT"
        header.letterSpacing = 0.2f
        queue.addView(header, lp(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        val body = label(17f, Color.WHITE)
        body.gravity = Gravity.CENTER
        body.setLineSpacing(dp(8).toFloat(), 1f)
        val bl = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        bl.topMargin = dp(14)
        queue.addView(body, bl)
        queueBody = body
        queueBox = queue
        center.addView(
            queue,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
    }

    /** Secondary actions sit in the free row above the track title. */
    private fun buildSecondaryControls() {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER
        row.weightSum = 5f

        favButton = null
        shuffleButton = null
        repeatButton = null

        if (LockState.flag("showSeekButtons", true)) {
            row.addView(cell(iconButton(R.drawable.ic_ls_rew, 44) { seekBy(-10_000) }))
        }
        if (LockState.flag("showFavorite", true)) {
            val b = iconButton(R.drawable.ic_ls_fav_off, 44) {
                LockState.optimisticFavorite(!LockState.favorite)
                LockState.command("favorite")
            }
            favButton = b
            row.addView(cell(b))
        }
        if (LockState.flag("showShuffle", false)) {
            val b = iconButton(R.drawable.ic_ls_shuffle, 44) { LockState.command("shuffle") }
            shuffleButton = b
            row.addView(cell(b))
        }
        if (LockState.flag("showRepeat", true)) {
            val b = iconButton(R.drawable.ic_ls_repeat, 44) { LockState.command("repeat") }
            repeatButton = b
            row.addView(cell(b))
        }
        if (LockState.flag("showSeekButtons", true)) {
            row.addView(cell(iconButton(R.drawable.ic_ls_ff, 44) { seekBy(10_000) }))
        }

        val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        l.topMargin = dp(4)
        l.bottomMargin = dp(4)
        content.addView(row, l)
    }

    private fun buildInfoRow() {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER_VERTICAL

        titleText = null
        artistText = null
        albumText = null
        val col = LinearLayout(this)
        col.orientation = LinearLayout.VERTICAL
        col.gravity = Gravity.CENTER_HORIZONTAL

        if (LockState.flag("showTitle", true)) {
            val t = label(24f, Color.WHITE, true)
            t.gravity = Gravity.CENTER
            t.setSingleLine(true)
            t.ellipsize = TextUtils.TruncateAt.MARQUEE
            t.marqueeRepeatLimit = -1
            t.isSelected = true
            titleText = t
            col.addView(t, lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
        if (LockState.flag("showArtist", true)) {
            val a = label(16f, 0xFFD0D0D0.toInt())
            a.gravity = Gravity.CENTER
            a.setSingleLine(true)
            a.ellipsize = TextUtils.TruncateAt.END
            artistText = a
            val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            l.topMargin = dp(4)
            col.addView(a, l)
        }
        if (LockState.flag("showAlbum", true)) {
            val a = label(14f, 0xFF9A9A9A.toInt())
            a.gravity = Gravity.CENTER
            a.setSingleLine(true)
            a.ellipsize = TextUtils.TruncateAt.END
            albumText = a
            val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            l.topMargin = dp(3)
            col.addView(a, l)
        }
        row.addView(col, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        l.topMargin = dp(8)
        content.addView(row, l)
    }

    private fun buildSeekRow() {
        seekBar = null
        leftTime = null
        rightTime = null
        if (!LockState.flag("showSeekbar", true)) return

        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER_VERTICAL

        val left = label(13f, 0xFFE0E0E0.toInt())
        left.minWidth = dp(52)
        left.gravity = Gravity.START
        val right = label(13f, 0xFFE0E0E0.toInt())
        right.minWidth = dp(52)
        right.gravity = Gravity.END

        val bar = SeekBar(this)
        bar.progressTintList = ColorStateList.valueOf(accent)
        bar.thumbTintList = ColorStateList.valueOf(Color.WHITE)
        bar.progressBackgroundTintList = ColorStateList.valueOf(0x44FFFFFF)
        bar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar, progress: Int, fromUser: Boolean) {
                if (fromUser) updateTimeLabels(progress.toLong())
            }

            override fun onStartTrackingTouch(sb: SeekBar) {
                scrubbing = true
            }

            override fun onStopTrackingTouch(sb: SeekBar) {
                scrubbing = false
                val ms = sb.progress.toLong()
                LockState.optimisticSeek(ms)
                LockState.command("seek", ms / 1000.0)
            }
        })

        row.addView(left, lp(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        row.addView(bar, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(right, lp(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        leftTime = left
        rightTime = right
        seekBar = bar
        val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        l.topMargin = dp(10)
        content.addView(row, l)
    }

    private fun cell(view: View, weight: Float = 1f): FrameLayout {
        val f = FrameLayout(this)
        f.addView(view, FrameLayout.LayoutParams(view.layoutParams.width, view.layoutParams.height, Gravity.CENTER))
        f.layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight)
        return f
    }

    private fun buildControls() {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.gravity = Gravity.CENTER_VERTICAL

        val prevNext = LockState.flag("showPrevNext", true)
        val availableWidthDp = (resources.displayMetrics.widthPixels / resources.displayMetrics.density).toInt() - 40
        val narrowLayout = availableWidthDp < 320
        val baseSideButtonSize = if (narrowLayout) 88 else 100
        val basePlayButtonSize = if (narrowLayout) 104 else 116
        val requestedScale = LockState.number("transportButtonScale", 100).coerceIn(70, 130) / 100f
        val baseTotalWidth = if (prevNext) {
            baseSideButtonSize * 2 + basePlayButtonSize
        } else {
            basePlayButtonSize
        }
        // Keep the scaled controls inside the usable screen width on small devices.
        val widthLimitedScale = (availableWidthDp - 8).coerceAtLeast(1).toFloat() / baseTotalWidth
        val scale = min(requestedScale, widthLimitedScale).coerceAtLeast(0.55f)
        val sideButtonSize = (baseSideButtonSize * scale).toInt().coerceAtLeast(48)
        val playButtonSize = (basePlayButtonSize * scale).toInt().coerceAtLeast(56)
        if (prevNext) {
            val previous = iconButton(R.drawable.ic_ls_prev, sideButtonSize, paddingDp = 2) {
                LockState.command("prev")
            }
            previous.setColorFilter(Color.WHITE)
            row.addView(cell(previous))
        }

        val play = ImageView(this)
        play.scaleType = ImageView.ScaleType.CENTER_INSIDE
        play.setPadding(dp(2), dp(2), dp(2), dp(2))
        play.background = null
        play.setImageResource(R.drawable.ic_ls_pause)
        play.setColorFilter(Color.WHITE)
        play.layoutParams = ViewGroup.LayoutParams(dp(playButtonSize), dp(playButtonSize))
        play.setOnClickListener {
            LockState.optimisticPlaying(!LockState.playing)
            LockState.command("playPause")
        }
        playButton = play
        row.addView(cell(play, 1.2f))

        if (prevNext) {
            val next = iconButton(R.drawable.ic_ls_next, sideButtonSize, paddingDp = 2) {
                LockState.command("next")
            }
            next.setColorFilter(Color.WHITE)
            row.addView(cell(next))
        }

        val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        l.topMargin = dp(8)
        content.addView(row, l)
    }

    private fun buildSlider() {
        slide = SlideToUnlockView(this)
        slide.accent = accent
        slide.onUnlock = { unlock() }
        val l = lp(ViewGroup.LayoutParams.MATCH_PARENT, dp(62))
        l.topMargin = dp(20)
        content.addView(slide, l)
    }

    // ------------------------------------------------------------------ behaviour

    private fun setMode(target: Int) {
        mode = if (mode == target) 0 else target
        applyMode()
        bindAll()
    }

    private fun applyMode() {
        coverFrame?.visibility = if (mode == 0) View.VISIBLE else View.GONE
        lyricsBox?.visibility = if (mode == 1) View.VISIBLE else View.GONE
        queueBox?.visibility = if (mode == 2) View.VISIBLE else View.GONE
        tint(lyricsButton, if (mode == 1) accent else 0xFFDDDDDD.toInt())
        tint(queueButton, if (mode == 2) accent else 0xFFDDDDDD.toInt())
    }

    private fun seekBy(deltaMs: Long) {
        LockState.optimisticSeek(LockState.positionMs() + deltaMs)
        LockState.command("seekBy", deltaMs / 1000.0)
    }

    private fun unlock() {
        if (previewMode) {
            finishAndRemoveTask()
            return
        }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (!km.isKeyguardLocked) {
            finishAndRemoveTask()
            return
        }
        try {
            km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    finishAndRemoveTask()
                }

                override fun onDismissCancelled() {
                    slide.reset()
                }

                override fun onDismissError() {
                    slide.reset()
                }
            })
        } catch (_: Throwable) {
            slide.reset()
        }
    }

    private fun onStateChanged() {
        if (isFinishing || isDestroyed) return
        if (optionsSignature() != lastOptsSignature) {
            buildUi()
            slide.setAnimating(true)
        }
        bindAll()
    }

    // ------------------------------------------------------------------ binding

    private fun bindAll() {
        val s = LockState
        titleText?.text = if (s.title.isEmpty()) "Nothing playing" else s.title
        artistText?.text = s.artist
        artistText?.visibility = if (s.artist.isEmpty()) View.GONE else View.VISIBLE
        albumText?.text = s.album
        albumText?.visibility = if (s.album.isEmpty()) View.GONE else View.VISIBLE
        coverLetter?.text = if (s.title.isEmpty()) "" else s.title.substring(0, 1).uppercase(Locale.getDefault())

        playButton?.setImageResource(if (s.playing) R.drawable.ic_ls_pause else R.drawable.ic_ls_play)
        playButton?.setColorFilter(Color.WHITE)
        favButton?.setImageResource(if (s.favorite) R.drawable.ic_ls_fav_on else R.drawable.ic_ls_fav_off)
        tint(favButton, if (s.favorite) 0xFFFF2056.toInt() else Color.WHITE)
        tint(shuffleButton, if (s.shuffle) accent else 0x99FFFFFF.toInt())
        repeatButton?.setImageResource(
            if (s.repeat == "one") R.drawable.ic_ls_repeat_one else R.drawable.ic_ls_repeat
        )
        tint(repeatButton, if (s.repeat == "off") 0x99FFFFFF.toInt() else accent)

        updateSpin()
        loadCover()
        bindTick()
        bindQueue()
    }

    private fun bindTick() {
        bindClock()
        bindSeek()
        if (mode == 1) bindLyrics()
    }

    private fun bindClock() {
        val c = clockText
        val d = dateText
        val now = Date()
        if (c != null) {
            val pattern = when (LockState.text("clockFormat", "system")) {
                "12h" -> "h:mm"
                "24h" -> "HH:mm"
                else -> if (DateFormat.is24HourFormat(this)) "HH:mm" else "h:mm"
            }
            val text = SimpleDateFormat(pattern, Locale.getDefault()).format(now)
            if (text != lastClock) {
                lastClock = text
                c.text = text
            }
        }
        if (d != null) {
            val text = SimpleDateFormat("MMM d, EEE", Locale.getDefault()).format(now)
            if (text != lastDate) {
                lastDate = text
                d.text = text
            }
        }
    }

    private fun updateTimeLabels(posMs: Long) {
        val dur = LockState.durationMs
        if (LockState.flag("remainingTime", true)) {
            leftTime?.text = "-" + fmt(dur - posMs)
        } else {
            leftTime?.text = fmt(posMs)
        }
        rightTime?.text = fmt(dur)
    }

    private fun bindSeek() {
        val bar = seekBar ?: return
        if (scrubbing) return
        val dur = LockState.durationMs
        val pos = LockState.positionMs()
        val max = if (dur > Int.MAX_VALUE) Int.MAX_VALUE else dur.toInt()
        if (bar.max != max) bar.max = max
        bar.progress = min(pos, max.toLong()).toInt()
        updateTimeLabels(pos)
    }

    private fun currentLyricIndex(posSec: Double): Int {
        val l = LockState.lyrics
        var lo = 0
        var hi = l.size - 1
        var result = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (l[mid].first <= posSec) {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private fun bindLyrics() {
        val views = lyricViews
        if (views.size < 5) return
        val lyrics = LockState.lyrics
        if (lyrics.isEmpty()) {
            for (i in 0 until 5) {
                views[i].text = if (i == 2) "No synced lyrics for this track" else ""
                views[i].alpha = if (i == 2) 0.7f else 0f
            }
            return
        }
        val cur = max(0, currentLyricIndex(LockState.positionMs() / 1000.0))
        for (i in 0 until 5) {
            val idx = cur + i - 2
            if (idx in lyrics.indices) {
                val line = lyrics[idx].second
                views[i].text = if (line.isBlank()) "♪" else line
                views[i].alpha = if (i == 2) 1f else (if (i == 1 || i == 3) 0.55f else 0.3f)
            } else {
                views[i].text = ""
                views[i].alpha = 0f
            }
        }
        views[2].setTextColor(accent)
    }

    private fun bindQueue() {
        val body = queueBody ?: return
        val q = LockState.queue
        body.text = if (q.isEmpty()) "Queue is empty" else {
            val sb = StringBuilder()
            for (i in q.indices) {
                if (i > 0) sb.append('\n')
                sb.append(i + 1).append("   ").append(q[i])
            }
            sb.toString()
        }
    }

    private fun updateSpin() {
        val frame = coverFrame ?: return
        val wantSpin = LockState.flag("coverSpin", false) &&
            LockState.text("coverShape", "rounded") == "circle"
        if (!wantSpin) {
            spin?.cancel()
            spin = null
            frame.rotation = 0f
            return
        }
        var anim = spin
        if (anim == null) {
            anim = android.animation.ObjectAnimator.ofFloat(frame, View.ROTATION, 0f, 360f)
            anim.duration = 14000
            anim.repeatCount = android.animation.ValueAnimator.INFINITE
            anim.interpolator = android.view.animation.LinearInterpolator()
            spin = anim
        }
        if (LockState.playing) {
            if (anim.isPaused) anim.resume() else if (!anim.isStarted) anim.start()
        } else if (anim.isRunning) {
            anim.pause()
        }
    }

    private fun loadCover() {
        val path = LockState.coverPath
        if (path == loadedCover) return
        loadedCover = path
        if (path == null) {
            applyCover(null, null)
            return
        }
        try {
            io.execute {
                val bmp = decode(path, 900)
                val small = if (bmp != null) {
                    val w = 48
                    val h = max(1, 48 * bmp.height / max(1, bmp.width))
                    Bitmap.createScaledBitmap(bmp, w, h, true)
                } else null
                ui.post {
                    if (!isFinishing && !isDestroyed && loadedCover == path) applyCover(bmp, small)
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun decode(path: String, maxSide: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options()
            bounds.inJustDecodeBounds = true
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (bounds.outWidth / sample > maxSide * 2 || bounds.outHeight / sample > maxSide * 2) {
                sample *= 2
            }
            val opts = BitmapFactory.Options()
            opts.inSampleSize = sample
            BitmapFactory.decodeFile(path, opts)
        } catch (_: Throwable) {
            null
        }
    }

    private fun applyCover(cover: Bitmap?, blurred: Bitmap?) {
        coverImage?.setImageBitmap(cover)
        coverImage?.visibility = if (cover == null) View.GONE else View.VISIBLE
        if (blurred != null && LockState.flag("blurBackground", true)) {
            bgImage.setImageBitmap(blurred)
            bgImage.visibility = View.VISIBLE
            if (Build.VERSION.SDK_INT >= 31) {
                bgImage.setRenderEffect(RenderEffect.createBlurEffect(28f, 28f, Shader.TileMode.CLAMP))
            }
        } else {
            bgImage.setImageDrawable(null)
            bgImage.visibility = View.GONE
        }
    }
}
