package ai.flutterclaw.flutterclaw

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import kotlin.math.*
import kotlin.random.Random

/**
 * Full-screen transparent overlay that draws sparkle/magic visual feedback
 * for UI automation actions: tap bursts, swipe trails, and type bubbles.
 *
 * Shares the same SYSTEM_ALERT_WINDOW permission as [OverlayStatusView].
 */
class TouchFeedbackOverlay private constructor(private val context: Context) {

    companion object {
        private const val TAG = "TouchFeedback"

        @Volatile private var instance: TouchFeedbackOverlay? = null

        fun getInstance(context: Context): TouchFeedbackOverlay {
            return instance ?: synchronized(this) {
                instance ?: TouchFeedbackOverlay(context.applicationContext).also { instance = it }
            }
        }

        // Sparkle symbols used by both tap and swipe
        val SPARKLES = charArrayOf('\u2728', '\u2B50', '\u2726', '\u2727', '\u22C6', '\u00B7')
        // Colors: purple, pink, gold, cyan, white, lavender, mint
        val SPARKLE_COLORS = intArrayOf(
            0xFFBB86FC.toInt(),
            0xFFFF79C6.toInt(),
            0xFFFFD700.toInt(),
            0xFF8BE9FD.toInt(),
            0xFFFFFFFF.toInt(),
            0xFFE0B0FF.toInt(),
            0xFF98FF98.toInt(),
        )
    }

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())
    private val density = context.resources.displayMetrics.density

    private fun canShow(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(context)

    private val overlayType: Int
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

    private fun fullScreenParams(): WindowManager.LayoutParams =
        WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

    private fun addAnimatedView(view: View, animator: ValueAnimator) {
        if (!canShow()) return
        try {
            windowManager.addView(view, fullScreenParams())
            animator.addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    handler.post {
                        try { windowManager.removeView(view) } catch (_: Exception) {}
                    }
                }
            })
            animator.start()
        } catch (e: Exception) {
            Log.e(TAG, "addAnimatedView failed", e)
        }
    }

    // ─── Tap sparkle burst ─────────────────────────────────────────────────────

    fun showTap(x: Float, y: Float) {
        Log.d(TAG, "showTap($x, $y)")
        handler.post { showTapInternal(x, y) }
    }

    private fun showTapInternal(x: Float, y: Float) {
        val view = SparkBurstView(context, x, y, density)
        addAnimatedView(view, view.animator)
    }

    // ─── Swipe sparkle trail ───────────────────────────────────────────────────

    fun showSwipe(x1: Float, y1: Float, x2: Float, y2: Float) {
        Log.d(TAG, "showSwipe($x1,$y1 -> $x2,$y2)")
        handler.post { showSwipeInternal(x1, y1, x2, y2) }
    }

    private fun showSwipeInternal(x1: Float, y1: Float, x2: Float, y2: Float) {
        val view = SparkTrailView(context, x1, y1, x2, y2, density)
        addAnimatedView(view, view.animator)
    }

    // ─── Type text bubble ──────────────────────────────────────────────────────

    fun showType(text: String) {
        Log.d(TAG, "showType('$text')")
        handler.post { showTypeInternal(text) }
    }

    private fun showTypeInternal(text: String) {
        if (!canShow()) return
        val view = TypeBubbleView(context, text, density)
        val anim = view.animator
        try {
            windowManager.addView(view, fullScreenParams())
            anim.addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    handler.post {
                        try { windowManager.removeView(view) } catch (_: Exception) {}
                    }
                }
            })
            anim.start()
        } catch (e: Exception) {
            Log.e(TAG, "showType addView failed", e)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Sparkle Burst — radiating particles from tap point
    // ═══════════════════════════════════════════════════════════════════════════

    private class SparkBurstView(
        context: Context,
        private val cx: Float,
        private val cy: Float,
        private val density: Float,
    ) : View(context) {

        data class Particle(
            val angle: Float,    // radians
            val speed: Float,    // px per progress unit
            val size: Float,     // text size
            val color: Int,
            val char: Char,
            val rotSpeed: Float, // rotation speed
            val delay: Float,    // 0..0.2 stagger
        )

        private val particles: List<Particle>
        private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            maskFilter = BlurMaskFilter(12f * density, BlurMaskFilter.Blur.NORMAL)
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
        }
        private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f * density
            color = 0xFFBB86FC.toInt()
        }
        private val ringPaint2 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f * density
            color = 0xFFFFD700.toInt()
        }
        private val vignettePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private var progress = 0f
        private var screenW = 0
        private var screenH = 0

        val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 900
            interpolator = DecelerateInterpolator(1.5f)
            addUpdateListener {
                progress = it.animatedValue as Float
                invalidate()
            }
        }

        init {
            // Layer type for blur filter
            setLayerType(LAYER_TYPE_SOFTWARE, null)

            val count = 20
            particles = (0 until count).map { i ->
                val baseAngle = (2.0 * Math.PI * i / count).toFloat()
                Particle(
                    angle = baseAngle + Random.nextFloat() * 0.4f - 0.2f,
                    speed = (55f + Random.nextFloat() * 65f) * density,
                    size = (8f + Random.nextFloat() * 12f) * density,
                    color = SPARKLE_COLORS[Random.nextInt(SPARKLE_COLORS.size)],
                    char = SPARKLES[Random.nextInt(SPARKLES.size)],
                    rotSpeed = (Random.nextFloat() - 0.5f) * 720f,
                    delay = Random.nextFloat() * 0.18f,
                )
            }
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            screenW = w
            screenH = h
        }

        override fun onDraw(canvas: Canvas) {
            // Subtle vignette flash on impact (first 25% of animation)
            if (progress < 0.25f && screenW > 0) {
                val flashAlpha = ((1f - progress / 0.25f) * 25).toInt()
                val radGrad = RadialGradient(
                    cx, cy,
                    maxOf(screenW, screenH).toFloat() * 0.7f,
                    intArrayOf(0x00000000, (flashAlpha shl 24) or 0xBB86FC),
                    floatArrayOf(0.3f, 1f),
                    Shader.TileMode.CLAMP,
                )
                vignettePaint.shader = radGrad
                canvas.drawRect(0f, 0f, screenW.toFloat(), screenH.toFloat(), vignettePaint)
                vignettePaint.shader = null
            }

            // Outer expanding ring (purple)
            val ringProgress = (progress * 1.5f).coerceAtMost(1f)
            val ringRadius = 45f * density * ringProgress
            ringPaint.alpha = ((1f - ringProgress) * 180).toInt()
            canvas.drawCircle(cx, cy, ringRadius, ringPaint)

            // Inner expanding ring (gold, slightly delayed)
            val ring2Progress = ((progress - 0.05f) * 1.6f).coerceIn(0f, 1f)
            if (ring2Progress > 0f) {
                val ring2Radius = 30f * density * ring2Progress
                ringPaint2.alpha = ((1f - ring2Progress) * 150).toInt()
                canvas.drawCircle(cx, cy, ring2Radius, ringPaint2)
            }

            // Central glow (larger, more vivid)
            if (progress < 0.5f) {
                val glowAlpha = ((1f - progress * 2f) * 160).toInt()
                glowPaint.color = (glowAlpha shl 24) or (0xBB86FC and 0x00FFFFFF)
                canvas.drawCircle(cx, cy, 25f * density * (1f - progress), glowPaint)
            }

            // Particles
            for (p in particles) {
                val t = ((progress - p.delay) / (1f - p.delay)).coerceIn(0f, 1f)
                if (t <= 0f) continue
                val dist = p.speed * t
                val px = cx + cos(p.angle.toDouble()).toFloat() * dist
                val py = cy + sin(p.angle.toDouble()).toFloat() * dist
                val alpha = ((1f - t) * 255).toInt().coerceIn(0, 255)
                val scale = 1f - t * 0.3f

                // Glow behind particle
                glowPaint.color = (((alpha * 0.4f).toInt()) shl 24) or (p.color and 0x00FFFFFF)
                canvas.drawCircle(px, py, p.size * 0.7f * scale, glowPaint)

                // Sparkle character
                textPaint.textSize = p.size * scale
                textPaint.color = (alpha shl 24) or (p.color and 0x00FFFFFF)
                canvas.save()
                canvas.rotate(p.rotSpeed * t, px, py)
                canvas.drawText(p.char.toString(), px, py + p.size * 0.35f * scale, textPaint)
                canvas.restore()
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Sparkle Trail — particles along swipe path
    // ═══════════════════════════════════════════════════════════════════════════

    private class SparkTrailView(
        context: Context,
        private val x1: Float,
        private val y1: Float,
        private val x2: Float,
        private val y2: Float,
        private val density: Float,
    ) : View(context) {

        data class TrailParticle(
            val t: Float,        // position along path 0..1
            val baseOffX: Float, // base perpendicular offset
            val baseOffY: Float,
            val wobbleAmp: Float,// sinusoidal wobble amplitude
            val wobbleFreq: Float,
            val size: Float,
            val color: Int,
            val char: Char,
        )

        private val trailParticles: List<TrailParticle>
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
        }
        private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            maskFilter = BlurMaskFilter(10f * density, BlurMaskFilter.Blur.NORMAL)
        }
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeWidth = 3.5f * density
        }
        private var progress = 0f

        private val perpX: Float
        private val perpY: Float

        val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1000
            interpolator = DecelerateInterpolator(1.2f)
            addUpdateListener {
                progress = it.animatedValue as Float
                invalidate()
            }
        }

        init {
            setLayerType(LAYER_TYPE_SOFTWARE, null)

            val dx = x2 - x1
            val dy = y2 - y1
            val len = sqrt(dx * dx + dy * dy)
            perpX = if (len > 0) -dy / len else 0f
            perpY = if (len > 0) dx / len else 0f

            val count = 24
            trailParticles = (0 until count).map {
                val posT = it.toFloat() / (count - 1)
                val spread = (Random.nextFloat() - 0.5f) * 20f * density
                TrailParticle(
                    t = posT,
                    baseOffX = perpX * spread,
                    baseOffY = perpY * spread,
                    wobbleAmp = (8f + Random.nextFloat() * 14f) * density,
                    wobbleFreq = 2f + Random.nextFloat() * 2f,
                    size = (8f + Random.nextFloat() * 8f) * density,
                    color = SPARKLE_COLORS[Random.nextInt(SPARKLE_COLORS.size)],
                    char = SPARKLES[Random.nextInt(SPARKLES.size)],
                )
            }
        }

        override fun onDraw(canvas: Canvas) {
            val drawPhase = (progress / 0.50f).coerceAtMost(1f)
            val fadePhase = ((progress - 0.50f) / 0.50f).coerceIn(0f, 1f)
            val baseAlpha = ((1f - fadePhase) * 255).toInt()

            // Gradient trail line (purple → cyan → gold)
            val ex = x1 + (x2 - x1) * drawPhase
            val ey = y1 + (y2 - y1) * drawPhase
            if (drawPhase > 0f) {
                linePaint.shader = LinearGradient(
                    x1, y1, ex, ey,
                    intArrayOf(0xFFBB86FC.toInt(), 0xFF8BE9FD.toInt(), 0xFFFFD700.toInt()),
                    floatArrayOf(0f, 0.5f, 1f),
                    Shader.TileMode.CLAMP,
                )
                linePaint.alpha = (baseAlpha * 0.5f).toInt()
                canvas.drawLine(x1, y1, ex, ey, linePaint)
                linePaint.shader = null
            }

            // Sparkle particles along path with sinusoidal wobble
            for (p in trailParticles) {
                val appear = (drawPhase - p.t).coerceIn(0f, 1f)
                if (appear <= 0f) continue

                // Wobble perpendicular to the path
                val wobble = sin((p.t * p.wobbleFreq + progress * 3f).toDouble()).toFloat() * p.wobbleAmp * appear
                val px = x1 + (x2 - x1) * p.t + p.baseOffX + perpX * wobble
                val py = y1 + (y2 - y1) * p.t + p.baseOffY + perpY * wobble
                val particleAlpha = (baseAlpha * appear).toInt().coerceIn(0, 255)
                val scale = 0.5f + appear * 0.5f

                // Glow
                glowPaint.color = ((particleAlpha * 0.35f).toInt() shl 24) or (p.color and 0x00FFFFFF)
                canvas.drawCircle(px, py, p.size * 0.6f * scale, glowPaint)

                // Sparkle character
                textPaint.textSize = p.size * scale
                textPaint.color = (particleAlpha shl 24) or (p.color and 0x00FFFFFF)
                canvas.drawText(p.char.toString(), px, py + p.size * 0.35f * scale, textPaint)
            }

            // Leading comet head (larger, pulsing glow)
            if (drawPhase > 0f && fadePhase < 0.8f) {
                val headAlpha = (baseAlpha * 0.95f).toInt()
                // Pulsing glow
                val pulse = 1f + 0.2f * sin((progress * 12f).toDouble()).toFloat()
                glowPaint.color = (headAlpha / 2 shl 24) or 0xFFD700
                canvas.drawCircle(ex, ey, 18f * density * pulse, glowPaint)
                // Main sparkle
                textPaint.textSize = 24f * density * pulse
                textPaint.color = (headAlpha shl 24) or 0xFFD700
                canvas.drawText("\u2728", ex, ey, textPaint)

                // Mini exhaust particles behind the head
                for (i in 1..3) {
                    val trail = i * 0.04f
                    val trailT = (drawPhase - trail).coerceAtLeast(0f)
                    val tx = x1 + (x2 - x1) * trailT
                    val ty = y1 + (y2 - y1) * trailT
                    val ta = (headAlpha * (1f - i * 0.25f)).toInt()
                    val ts = (6f + i * 2f) * density
                    textPaint.textSize = ts
                    textPaint.color = (ta shl 24) or SPARKLE_COLORS[i % SPARKLE_COLORS.size] and 0x00FFFFFF or (ta shl 24)
                    canvas.drawText(SPARKLES[i % SPARKLES.size].toString(), tx, ty, textPaint)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Type Bubble — keyboard icon + text
    // ═══════════════════════════════════════════════════════════════════════════

    private class TypeBubbleView(
        context: Context,
        private val text: String,
        private val density: Float,
    ) : View(context) {

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f * density
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFFFFF.toInt()
            textSize = 14f * density * resources.displayMetrics.scaledDensity / density
            typeface = Typeface.DEFAULT_BOLD
            setShadowLayer(4f * density, 0f, 0f, 0x80BB86FC.toInt())
        }
        private val sparklePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
        }
        private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            maskFilter = BlurMaskFilter(6f * density, BlurMaskFilter.Blur.NORMAL)
        }
        private val padH = 20f * density
        private val padV = 12f * density
        private val cornerRadius = 24f * density

        private val displayText: String = run {
            val prefix = "\u2728\u2328 " // sparkle + keyboard
            val maxLen = 40
            val truncated = if (text.length > maxLen) text.take(maxLen) + "\u2026" else text
            prefix + truncated
        }

        // Corner sparkle positions (relative to pill rect, set in onDraw)
        data class CornerSparkle(
            val relX: Float, // 0..1 relative to pill width
            val relY: Float, // 0..1 relative to pill height
            val char: Char,
            val color: Int,
            val phase: Float, // twinkle phase offset
        )

        private val cornerSparkles = (0 until 4).map {
            CornerSparkle(
                relX = if (it % 2 == 0) Random.nextFloat() * 0.2f else 0.8f + Random.nextFloat() * 0.2f,
                relY = if (it < 2) -0.3f - Random.nextFloat() * 0.4f else 1.1f + Random.nextFloat() * 0.3f,
                char = SPARKLES[Random.nextInt(SPARKLES.size)],
                color = SPARKLE_COLORS[Random.nextInt(SPARKLE_COLORS.size)],
                phase = Random.nextFloat() * 6.28f,
            )
        }

        private var progress = 0f

        val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1800
            addUpdateListener {
                progress = it.animatedValue as Float
                invalidate()
            }
        }

        init {
            setLayerType(LAYER_TYPE_SOFTWARE, null)
        }

        override fun onDraw(canvas: Canvas) {
            val tw = textPaint.measureText(displayText)
            val th = textPaint.textSize
            val pillW = tw + padH * 2
            val pillH = th + padV * 2
            val left = (width - pillW) / 2f
            val top = 80f * density

            // Entry: bounce scale 0.8→1.05→1.0 in first 15%, then hold
            // Exit: fade out alpha in last 20%
            val entryT = (progress / 0.15f).coerceAtMost(1f)
            val bounceScale = if (entryT < 1f) {
                0.8f + 0.25f * entryT // overshoot to 1.05
            } else {
                1.0f
            }
            val fadeAlpha = if (progress > 0.80f) {
                ((1f - (progress - 0.80f) / 0.20f) * 255).toInt().coerceIn(0, 255)
            } else {
                255
            }

            val rect = RectF(left, top, left + pillW, top + pillH)

            canvas.save()
            canvas.scale(bounceScale, bounceScale, left + pillW / 2f, top + pillH / 2f)

            // Background gradient (dark purple to dark blue)
            bgPaint.shader = LinearGradient(
                left, top, left + pillW, top + pillH,
                0xDD1A1A2E.toInt(), 0xDD0D1B2A.toInt(),
                Shader.TileMode.CLAMP,
            )
            bgPaint.alpha = fadeAlpha
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, bgPaint)
            bgPaint.shader = null

            // Animated gradient border (rotating sweep)
            val borderAngle = progress * 720f // 2 full rotations over animation
            val cx = left + pillW / 2f
            val cy = top + pillH / 2f
            borderPaint.shader = SweepGradient(
                cx, cy,
                intArrayOf(
                    0xFFBB86FC.toInt(),
                    0xFFFF79C6.toInt(),
                    0xFFFFD700.toInt(),
                    0xFF8BE9FD.toInt(),
                    0xFFBB86FC.toInt(),
                ),
                null,
            )
            // Rotate the sweep gradient
            val matrix = Matrix()
            matrix.postRotate(borderAngle, cx, cy)
            borderPaint.shader!!.setLocalMatrix(matrix)
            borderPaint.alpha = fadeAlpha
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, borderPaint)

            // Text
            textPaint.alpha = fadeAlpha
            canvas.drawText(
                displayText,
                left + padH,
                top + padV + th - textPaint.descent(),
                textPaint,
            )

            canvas.restore()

            // Corner sparkles that twinkle
            for (s in cornerSparkles) {
                val twinkle = ((sin((progress * 8f + s.phase).toDouble()) + 1f) / 2f).toFloat()
                val sparkAlpha = (fadeAlpha * twinkle * 0.8f).toInt().coerceIn(0, 255)
                if (sparkAlpha < 10) continue

                val sx = left + pillW * s.relX
                val sy = top + pillH * s.relY
                val sparkSize = (10f + twinkle * 6f) * density * bounceScale

                // Glow
                glowPaint.color = (sparkAlpha / 3 shl 24) or (s.color and 0x00FFFFFF)
                canvas.drawCircle(sx, sy, sparkSize * 0.5f, glowPaint)

                // Character
                sparklePaint.textSize = sparkSize
                sparklePaint.color = (sparkAlpha shl 24) or (s.color and 0x00FFFFFF)
                canvas.drawText(s.char.toString(), sx, sy + sparkSize * 0.35f, sparklePaint)
            }
        }
    }
}
