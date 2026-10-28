package com.aether.music

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.abs
import kotlin.math.min

/** Pill-shaped "slide to unlock" control: drag the lock knob to the end to unlock. */
class SlideToUnlockView(context: Context) : View(context) {
    var onUnlock: (() -> Unit)? = null

    var accent: Int = Color.WHITE
        set(value) {
            field = value
            invalidate()
        }

    private val density = resources.displayMetrics.density
    private val pad = 4f * density

    private var progress = 0f
    private var dragging = false
    private var grabOffset = 0f
    private var shimmer = 0f
    private var settle: ValueAnimator? = null

    private val rect = RectF()
    private val chevron = Path()

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF3A3A3A.toInt() }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f * density
        color = 0xFFE8E8E8.toInt()
    }
    private val knobPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val chevPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 3.4f * density
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = Color.WHITE
    }
    private val lockIcon: Drawable? = context.getDrawable(R.drawable.ic_ls_lock)?.mutate()

    private val shimmerAnim = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1500
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            shimmer = it.animatedValue as Float
            invalidate()
        }
    }

    init {
        contentDescription = "Slide to unlock"
    }

    fun setAnimating(on: Boolean) {
        if (on) {
            if (!shimmerAnim.isStarted) shimmerAnim.start()
        } else {
            shimmerAnim.cancel()
        }
    }

    fun reset() {
        animateTo(0f, null)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        setAnimating(true)
    }

    override fun onDetachedFromWindow() {
        setAnimating(false)
        settle?.cancel()
        super.onDetachedFromWindow()
    }

    private fun knobRadius(): Float = (height - 2f * pad) / 2f

    private fun travel(): Float = width - 2f * pad - 2f * knobRadius()

    private fun knobCenterX(): Float = pad + knobRadius() + progress * travel()

    private fun animateTo(target: Float, end: (() -> Unit)?) {
        settle?.cancel()
        val a = ValueAnimator.ofFloat(progress, target)
        a.duration = 180
        a.addUpdateListener {
            progress = it.animatedValue as Float
            invalidate()
        }
        a.addListener(object : AnimatorListenerAdapter() {
            private var cancelled = false

            override fun onAnimationCancel(animation: Animator) {
                cancelled = true
            }

            override fun onAnimationEnd(animation: Animator) {
                if (!cancelled) end?.invoke()
            }
        })
        settle = a
        a.start()
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val kx = knobCenterX()
                if (abs(e.x - kx) <= knobRadius() * 1.5f) {
                    dragging = true
                    settle?.cancel()
                    grabOffset = e.x - kx
                    parent?.requestDisallowInterceptTouchEvent(true)
                    return true
                }
                return false
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragging) return false
                val t = travel()
                if (t > 0f) {
                    val raw = (e.x - grabOffset - pad - knobRadius()) / t
                    progress = if (raw < 0f) 0f else if (raw > 1f) 1f else raw
                    invalidate()
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!dragging) return false
                dragging = false
                if (e.actionMasked == MotionEvent.ACTION_UP && progress >= 0.82f) {
                    performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    animateTo(1f) { onUnlock?.invoke() }
                } else {
                    animateTo(0f, null)
                }
                return true
            }
        }
        return super.onTouchEvent(e)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val inset = strokePaint.strokeWidth / 2f
        rect.set(inset, inset, w - inset, h - inset)
        val r = rect.height() / 2f
        canvas.drawRoundRect(rect, r, r, trackPaint)

        val cx = knobCenterX()
        if (progress > 0f) {
            fillPaint.color = (accent and 0x00FFFFFF) or (0x80 shl 24)
            canvas.save()
            canvas.clipRect(0f, 0f, cx, h)
            canvas.drawRoundRect(rect, r, r, fillPaint)
            canvas.restore()
        }
        canvas.drawRoundRect(rect, r, r, strokePaint)

        val fade = 1f - min(1f, progress * 2.2f)
        if (fade > 0f) {
            val spacing = 20f * density
            val midX = w / 2f + 14f * density
            for (i in 0..2) {
                var phase = (shimmer - i * 0.18f) % 1f
                if (phase < 0f) phase += 1f
                val tri = 1f - abs(phase * 2f - 1f)
                chevPaint.alpha = (255f * (0.3f + 0.7f * tri) * fade).toInt()
                val x = midX + (i - 1) * spacing
                val y = h / 2f
                chevron.reset()
                chevron.moveTo(x - 5f * density, y - 8f * density)
                chevron.lineTo(x + 4f * density, y)
                chevron.lineTo(x - 5f * density, y + 8f * density)
                canvas.drawPath(chevron, chevPaint)
            }
        }

        val kr = knobRadius()
        canvas.drawCircle(cx, h / 2f, kr, knobPaint)
        val icon = lockIcon
        if (icon != null) {
            val s = (kr * 0.95f).toInt()
            icon.setBounds(
                (cx - s / 2f).toInt(),
                (h / 2f - s / 2f).toInt(),
                (cx + s / 2f).toInt(),
                (h / 2f + s / 2f).toInt()
            )
            icon.setTint(Color.BLACK)
            icon.draw(canvas)
        }
    }
}
