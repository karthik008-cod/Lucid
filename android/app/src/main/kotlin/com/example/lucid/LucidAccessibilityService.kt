package com.example.lucid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.widget.ImageView
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.*
import kotlin.math.*
import kotlin.random.Random

class LucidAccessibilityService : AccessibilityService() {

    // ─── State ────────────────────────────────────────────────────────────────

    // Tracks the last *real* (non-ignored, non-recents) foreground package.
    // Never reset by recents/system-UI visits.
    private var currentApp = ""

    // Packages with an active granted session (timer completed).
    // Only cleared when user genuinely navigates to a non-target, non-ignored app.
    private val activeSessionApps = mutableSetOf<String>()

    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var warningRoot: FrameLayout? = null
    private var countdownTimer: CountDownTimer? = null
    private var usageTimer: CountDownTimer? = null

    // Animators for the loading screen
    private val activeAnimators = mutableListOf<ValueAnimator>()
    private var isLoadingScreenActive = false

    // Audio focus for pausing background playback
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    // 30 s for testing — change to 15 * 60 * 1000L for production
    private val WARNING_INTERVAL_MS = 30 * 1000L

    // Packages that must NEVER trigger the timer or be treated as "leaving" a target app.
    private val ignoredPackages = mutableSetOf(
        // Stock Android
        "com.android.systemui",
        "com.android.launcher",
        "com.android.launcher2",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        // MIUI / Redmi
        "com.miui.home",
        "com.miui.recents",         // ← recents: do NOT treat as "leaving" target
        "com.miui.systemui",
        "com.miui.securitycenter",
        "com.miui.global.packageinstaller",
        "com.miui.screenshot",
        // Samsung
        "com.sec.android.app.launcher",
        "com.samsung.android.app.cocktailbarservice",
        "com.sec.android.app.taskmanager",
        // Other OEMs
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.coloros.launcher",
        "com.vivo.launcher",
        "com.oneplus.launcher",
        "com.nothing.launcher",
        "com.realme.launcher",
        // Common system overlays / permission dialogs
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "android"
    )

    // ─── Target Apps ─────────────────────────────────────────────────────────

    private fun getTargetApps(): Set<String> {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.enabled_target_apps", "[]") ?: "[]"
        return raw
            .removePrefix("[").removeSuffix("]")
            .replace("\"", "")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        ignoredPackages.add(packageName)

        val info = AccessibilityServiceInfo()
        info.eventTypes  = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        info.flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                     AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        serviceInfo = info

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        Log.d("Lucid", "Service connected")
    }

    // ─── Event Routing ────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return

        // ── Always skip system UI, launchers, recents, dialogs ───────────────
        // IMPORTANT: recents is ignored here, so going to recents does NOT update
        // currentApp, which means returning from recents back to YouTube does NOT
        // trigger a new session/timer.
        if (ignoredPackages.contains(pkg)) return

        // ── Skip duplicate same-package events (tab switches, dialogs, etc.) ─
        // This is the fix for YouTube tab switches triggering the timer.
        if (pkg == currentApp && currentApp.isNotEmpty()) return

        val prev = currentApp
        currentApp = pkg

        val targets = getTargetApps()

        // ── Leaving a target app → only end session if going to a REAL non-target app ─
        // We only end the session if:
        //   1. prev was a target app
        //   2. The new app is NOT a target app
        //   (ignored packages never reach here, so this is safe)
        if (prev.isNotEmpty() && targets.contains(prev) && !targets.contains(currentApp)) {
            activeSessionApps.remove(prev)
            stopUsageTimer()
            Log.d("Lucid", "Left $prev → session ended (now at $currentApp)")
        }

        // ── Opened a target app ───────────────────────────────────────────────
        if (targets.contains(currentApp)) {
            if (activeSessionApps.contains(currentApp)) {
                // User returned to this app mid-session — no timer
                Log.d("Lucid", "Returned to $currentApp (active session) — no timer")
                return
            }
            if (!isLoadingScreenActive) {
                stopUsageTimer()
                showMindfulLoadingScreen()
            }
        }
    }

    // ─── Audio Focus (pauses background audio) ────────────────────────────────

    private fun requestAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                        .build()
                )
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener {}
                .build()
            audioFocusRequest = req
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    private fun releaseAudioFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }

    // ─── Loading Screen ───────────────────────────────────────────────────────

    private fun showMindfulLoadingScreen() {
        isLoadingScreenActive = true

        // PAUSE the underlying app's audio immediately
        requestAudioFocus()

        val blockedApp = currentApp
        val totalMs    = 60_000L
        val dp         = resources.displayMetrics.density

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // ── Root container ────────────────────────────────────────────────────
        val root = FrameLayout(this)

        // ── Dark deep-space gradient background ───────────────────────────────
        val bgView = object : View(this) {
            private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            override fun onDraw(canvas: Canvas) {
                bgPaint.shader = RadialGradient(
                    width / 2f, height * 0.4f, width.toFloat(),
                    intArrayOf(
                        Color.parseColor("#12003E"),
                        Color.parseColor("#0A0020"),
                        Color.parseColor("#03000D")
                    ),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
                )
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
            }
        }
        root.addView(bgView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Particle field layer ──────────────────────────────────────────────
        val particleView = createParticleView(dp)
        root.addView(particleView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Geometric mandala layer (rotating behind everything) ──────────────
        var mandalaRotation = 0f
        var mandalaRotation2 = 0f
        val mandalaView = object : View(this) {
            private val paint1 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.2f
                color = Color.parseColor("#33BB86FC")
            }
            private val paint2 = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 0.8f
                color = Color.parseColor("#2203DAC6")
            }
            override fun onDraw(canvas: Canvas) {
                val cx = width / 2f
                val cy = height / 2f

                // Outer rotating hexagon ring
                canvas.save()
                canvas.rotate(mandalaRotation, cx, cy)
                val r1 = width * 0.38f
                drawPolygon(canvas, cx, cy, r1, 6, paint1)
                drawPolygon(canvas, cx, cy, r1 * 0.85f, 6, paint1)
                for (i in 0 until 6) {
                    val angle = Math.toRadians(i * 60.0)
                    val x = cx + r1 * cos(angle).toFloat()
                    val y = cy + r1 * sin(angle).toFloat()
                    canvas.drawCircle(x, y, dp * 3f, paint1)
                }
                canvas.restore()

                // Inner counter-rotating star
                canvas.save()
                canvas.rotate(mandalaRotation2, cx, cy)
                val r2 = width * 0.22f
                drawPolygon(canvas, cx, cy, r2, 8, paint2)
                drawPolygon(canvas, cx, cy, r2 * 0.7f, 8, paint2)
                canvas.restore()
            }
        }

        // ── Scrollable content (single stack) ─────────────────────────────────
        val scroll = ScrollView(this).apply { isFillViewport = true }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity     = Gravity.CENTER_HORIZONTAL
            setPadding((dp * 28).toInt(), (dp * 60).toInt(), (dp * 28).toInt(), (dp * 40).toInt())
        }

        // ── Central energy orb + arc progress ─────────────────────────────────
        val orbSizePx = (dp * 320).toInt()
        val logoImage = ImageView(this).apply {
    setImageResource(R.mipmap.ic_launcher)
    scaleType = ImageView.ScaleType.FIT_CENTER
}
        var arcProgress = 1f
        var breathScale = 1f
        var energyPulse = 0f
        var shimmerAngle = 0f
        var orbGlow = 0f

        

        val orbView = object : View(this) {
            
            private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 8
                color = Color.parseColor("#1A1A35")
                strokeCap = Paint.Cap.ROUND
            }
            private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 8
                strokeCap = Paint.Cap.ROUND
            }
            private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 22
                strokeCap = Paint.Cap.ROUND
                maskFilter = BlurMaskFilter(dp * 14, BlurMaskFilter.Blur.NORMAL)
            }
            private val orbPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            private val orbGlowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                maskFilter = BlurMaskFilter(dp * 30, BlurMaskFilter.Blur.NORMAL)
            }
            private val innerRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.5f
                strokeCap = Paint.Cap.ROUND
            }
            private val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 2f
                strokeCap = Paint.Cap.ROUND
            }

            override fun onDraw(canvas: Canvas) {
                val cx = width / 2f
                val cy = height / 2f
                val pad = dp * 28
                val arcRect = RectF(pad, pad, width - pad, height - pad)
                val arcRadius = (width - 2 * pad) / 2f

                // ── Energy orb (center glowing ball) ─────────────────────────
                val orbRadius = arcRadius * 0.52f * breathScale
                val glowAlpha = (0.35f + orbGlow * 0.25f)
                orbGlowPaint.shader = RadialGradient(
                    cx, cy, orbRadius * 1.5f,
                    intArrayOf(
                        Color.argb((glowAlpha * 255).toInt(), 187, 134, 252),
                        Color.argb((glowAlpha * 100).toInt(), 124, 77, 255),
                        Color.TRANSPARENT
                    ),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
                )
                canvas.drawCircle(cx, cy, orbRadius * 1.5f, orbGlowPaint)

                orbPaint.shader = RadialGradient(
                    cx - orbRadius * 0.2f, cy - orbRadius * 0.3f, orbRadius,
                    intArrayOf(
                        Color.parseColor("#E8D5FF"),
                        Color.parseColor("#BB86FC"),
                        Color.parseColor("#5A1FC4")
                    ),
                    floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP
                )
                canvas.drawCircle(cx, cy, orbRadius, orbPaint)

                // Shimmer highlight on orb
                val shimX = cx + orbRadius * 0.3f * cos(shimmerAngle.toDouble()).toFloat()
                val shimY = cy + orbRadius * 0.3f * sin(shimmerAngle.toDouble()).toFloat()
                val shimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = RadialGradient(
                        shimX, shimY, orbRadius * 0.4f,
                        intArrayOf(Color.argb(140, 255, 255, 255), Color.TRANSPARENT),
                        floatArrayOf(0f, 1f), Shader.TileMode.CLAMP
                    )
                }
                canvas.drawCircle(shimX, shimY, orbRadius * 0.4f, shimPaint)

                // ── Tick marks around the ring ────────────────────────────────
                for (i in 0 until 60) {
                    val angle = Math.toRadians(i * 6.0 - 90.0)
                    val isMajor = i % 5 == 0
                    val innerR = arcRadius - dp * (if (isMajor) 6f else 3f)
                    val outerR = arcRadius - dp * 12f
                    val alpha = if (i.toFloat() / 60f > (1f - arcProgress)) 180 else 50
                    tickPaint.color = Color.argb(alpha, 187, 134, 252)
                    tickPaint.strokeWidth = dp * (if (isMajor) 2.5f else 1f)
                    canvas.drawLine(
                        cx + innerR * cos(angle).toFloat(),
                        cy + innerR * sin(angle).toFloat(),
                        cx + outerR * cos(angle).toFloat(),
                        cy + outerR * sin(angle).toFloat(),
                        tickPaint
                    )
                }

                // ── Track ring ────────────────────────────────────────────────
                canvas.drawOval(arcRect, trackPaint)

                // ── Gradient arc ──────────────────────────────────────────────
                val sweep = arcProgress * 360f
                val gradient = SweepGradient(
                    cx, cy,
                    intArrayOf(
                        Color.parseColor("#BB86FC"),
                        Color.parseColor("#7C4DFF"),
                        Color.parseColor("#03DAC6"),
                        Color.parseColor("#BB86FC")
                    ),
                    floatArrayOf(0f, 0.4f, 0.8f, 1f)
                )
                val matrix = Matrix()
                matrix.setRotate(-90f, cx, cy)
                gradient.setLocalMatrix(matrix)
                arcPaint.shader  = gradient
                glowPaint.shader = gradient
                canvas.drawArc(arcRect, -90f, sweep, false, glowPaint)
                canvas.drawArc(arcRect, -90f, sweep, false, arcPaint)

                // ── Energy pulse ring ─────────────────────────────────────────
                val pulseR = arcRadius * 0.6f + arcRadius * 0.35f * energyPulse
                val pulseAlpha = ((1f - energyPulse) * 160).toInt().coerceIn(0, 255)
                innerRingPaint.shader = SweepGradient(
                    cx, cy,
                    intArrayOf(
                        Color.argb(pulseAlpha, 187, 134, 252),
                        Color.argb(pulseAlpha / 2, 3, 218, 198),
                        Color.argb(pulseAlpha, 187, 134, 252)
                    ),
                    null
                )
                canvas.drawCircle(cx, cy, pulseR, innerRingPaint)
            }
        }

        // ── Animators ─────────────────────────────────────────────────────────

        // Breathing animator for the orb
        val breathAnimator = ValueAnimator.ofFloat(0.9f, 1.1f).apply {
            duration = 3000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = DecelerateInterpolator()
            addUpdateListener { breathScale = animatedValue as Float; orbView.invalidate() }
        }

        // Energy pulse
        val pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 2500
            repeatCount = ValueAnimator.INFINITE
            interpolator = DecelerateInterpolator()
            addUpdateListener { energyPulse = animatedValue as Float; orbView.invalidate() }
        }

        // Shimmer rotation
        val shimmerAnimator = ValueAnimator.ofFloat(0f, (2 * Math.PI).toFloat()).apply {
            duration = 4000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { shimmerAngle = animatedValue as Float; orbView.invalidate() }
        }

        // Orb glow pulse
        val glowAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener { orbGlow = animatedValue as Float; orbView.invalidate() }
        }

        // Mandala rotation
        val mandalaAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
            duration = 20000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                mandalaRotation = animatedValue as Float
                mandalaView.invalidate()
            }
        }
        val mandalaAnimator2 = ValueAnimator.ofFloat(360f, 0f).apply {
            duration = 15000
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                mandalaRotation2 = animatedValue as Float
                mandalaView.invalidate()
            }
        }

        activeAnimators.addAll(listOf(breathAnimator, pulseAnimator, shimmerAnimator, glowAnimator, mandalaAnimator, mandalaAnimator2))
        breathAnimator.start(); pulseAnimator.start(); shimmerAnimator.start()
        glowAnimator.start(); mandalaAnimator.start(); mandalaAnimator2.start()

        val orbLp = LinearLayout.LayoutParams(orbSizePx, orbSizePx).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val logoContainer = FrameLayout(this)

logoContainer.addView(
    orbView,
    FrameLayout.LayoutParams(
        orbSizePx,
        orbSizePx,
        Gravity.CENTER
    )
)

logoContainer.addView(
    logoImage,
    FrameLayout.LayoutParams(
        (dp * 170).toInt(),
        (dp * 170).toInt(),
        Gravity.CENTER
    )
)

content.addView(logoContainer, orbLp)

        // ── Seconds display below orb ─────────────────────────────────────────
        val secondsTv = TextView(this).apply {
            text = "60"
            setTextColor(Color.WHITE)
            textSize = 64f
            gravity  = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            setPadding(0, (dp * 8).toInt(), 0, 0)
            // Subtle shadow
            setShadowLayer(dp * 8, 0f, 0f, Color.parseColor("#88BB86FC"))
        }
        content.addView(secondsTv)

        val secLabelTv = TextView(this).apply {
            text = "SECONDS TO BREATHE"
            setTextColor(Color.parseColor("#88BB86FC"))
            textSize = 10f
            gravity  = Gravity.CENTER
            letterSpacing = 0.35f
        }
        content.addView(secLabelTv)

        // ── Mindfulness quote ─────────────────────────────────────────────────
        val quotes = listOf(
            "\"The present moment is the only time over which we have dominion.\"",
            "\"Almost everything will work again if you unplug it for a few minutes.\"",
            "\"Boredom is the gateway to creativity.\"",
            "\"Do you really need to scroll right now?\"",
            "\"Attention is the rarest and purest form of generosity.\""
        )
        val quoteTv = TextView(this).apply {
            text = quotes[Random.nextInt(quotes.size)]
            setTextColor(Color.parseColor("#88B0B0CC"))
            textSize = 12.5f
            gravity  = Gravity.CENTER
            setLineSpacing(0f, 1.6f)
            setPadding((dp * 8).toInt(), (dp * 20).toInt(), (dp * 8).toInt(), 0)
            setTypeface(Typeface.create("serif", Typeface.ITALIC))
        }
        content.addView(quoteTv)

        // ── Title ─────────────────────────────────────────────────────────────
        val titleTv = TextView(this).apply {
            text = "Take a Conscious Pause"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity  = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            letterSpacing = 0.02f
            setPadding(0, (dp * 20).toInt(), 0, 0)
            setShadowLayer(dp * 6, 0f, 2f, Color.parseColor("#66BB86FC"))
        }
        content.addView(titleTv)

        // ── Subtitle ──────────────────────────────────────────────────────────
        val subtitleTv = TextView(this).apply {
            text = "Your brain deserves a moment\nto decide if this is truly worth your time."
            setTextColor(Color.parseColor("#778899AA"))
            textSize = 13.5f
            gravity  = Gravity.CENTER
            setLineSpacing(0f, 1.6f)
            setPadding(0, (dp * 10).toInt(), 0, 0)
        }
        content.addView(subtitleTv)

        // ── 3 micro-stats chips ───────────────────────────────────────────────
        val chipRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, (dp * 24).toInt(), 0, 0)
        }
        listOf("🧘 Mindful", "📵 Focused", "✨ Present").forEach { label ->
            val chip = object : TextView(this) {
                private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.parseColor("#22BB86FC")
                }
                private val sp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp * 0.8f
                    color = Color.parseColor("#44BB86FC")
                }
                private val r = dp * 20f
                init { setWillNotDraw(false) }
                override fun onDraw(c: Canvas) {
                    val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                    c.drawRoundRect(rect, r, r, p)
                    c.drawRoundRect(rect, r, r, sp)
                    super.onDraw(c)
                }
            }.apply {
                text = label
                setTextColor(Color.parseColor("#BBBB86FC"))
                textSize = 12f
                setPadding((dp * 14).toInt(), (dp * 7).toInt(), (dp * 14).toInt(), (dp * 7).toInt())
                gravity = Gravity.CENTER
            }
            val chipLp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { setMargins((dp * 4).toInt(), 0, (dp * 4).toInt(), 0) }
            chipRow.addView(chip, chipLp)
        }
        content.addView(chipRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // ── Divider line ──────────────────────────────────────────────────────
        val divView = object : View(this) {
            private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    0f, 0f, 1f, 0f,
                    intArrayOf(Color.TRANSPARENT, Color.parseColor("#44BB86FC"), Color.TRANSPARENT),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
                )
                strokeWidth = dp * 1f
                style = Paint.Style.STROKE
            }
            override fun onDraw(canvas: Canvas) {
                linePaint.shader = LinearGradient(
                    0f, height / 2f, width.toFloat(), height / 2f,
                    intArrayOf(Color.TRANSPARENT, Color.parseColor("#44BB86FC"), Color.TRANSPARENT),
                    floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP
                )
                canvas.drawLine(0f, height / 2f, width.toFloat(), height / 2f, linePaint)
            }
        }
        content.addView(divView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (dp * 1).toInt()
        ).also { it.setMargins(0, (dp * 28).toInt(), 0, (dp * 24).toInt()) })

        // ── Go Back button ────────────────────────────────────────────────────
        val goBackBtn = object : TextView(this) {
            private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#22CF4444")
            }
            private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.2f
                color = Color.parseColor("#88CF4466")
            }
            private val cornerR = dp * 18f
            init { setWillNotDraw(false) }
            override fun onDraw(canvas: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                canvas.drawRoundRect(rect, cornerR, cornerR, bgPaint)
                canvas.drawRoundRect(rect, cornerR, cornerR, strokePaint)
                super.onDraw(canvas)
            }
        }.apply {
            text     = "← Leave & Do Something Better"
            setTextColor(Color.parseColor("#DDCF4466"))
            textSize = 15f
            gravity  = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            setPadding((dp * 24).toInt(), (dp * 18).toInt(), (dp * 24).toInt(), (dp * 18).toInt())
            setOnClickListener {
                currentApp = ""
                cancelAllAnimators()
                removeLoadingScreen()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }
        content.addView(goBackBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        scroll.addView(content, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Layer order: bg → particles → mandala → scroll content
        root.addView(mandalaView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ))
        root.addView(scroll, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Window flags: block touches to underlying app ─────────────────────
        // FLAG_NOT_TOUCH_MODAL blocks touch events from reaching underlying app.
        // This effectively pauses user interaction with the app behind the overlay.
        // We do NOT use FLAG_NOT_FOCUSABLE so the overlay captures all input.
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        windowManager?.addView(root, params)
        overlayRoot = root

        // Fade-in entrance
        root.alpha = 0f
        root.animate().alpha(1f).setDuration(500).start()

        // ── Countdown timer ───────────────────────────────────────────────────
        countdownTimer = object : CountDownTimer(totalMs, 100) {
            override fun onTick(millisUntilFinished: Long) {
                val secs = ((millisUntilFinished + 999) / 1000).coerceAtLeast(1)
                arcProgress = millisUntilFinished.toFloat() / totalMs
                Handler(Looper.getMainLooper()).post {
                    secondsTv.text = "$secs"
                    orbView.invalidate()
                }
            }
            override fun onFinish() {
                cancelAllAnimators()
                activeSessionApps.add(blockedApp)
                releaseAudioFocus()
                removeLoadingScreen()
                startUsageTimer()
            }
        }.start()
    }

    // Helper: draw a regular polygon
    private fun drawPolygon(canvas: Canvas, cx: Float, cy: Float, radius: Float, sides: Int, paint: Paint) {
        val path = Path()
        for (i in 0 until sides) {
            val angle = Math.toRadians(i * 360.0 / sides - 90.0)
            val x = cx + radius * cos(angle).toFloat()
            val y = cy + radius * sin(angle).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        canvas.drawPath(path, paint)
    }

    // Helper: create an animated particle field view
    private fun createParticleView(dp: Float): View {
        data class Particle(
            var x: Float, var y: Float,
            val speed: Float, val size: Float,
            val alpha: Float, val color: Int,
            var phase: Float
        )

        return object : View(this) {
            private val particles = mutableListOf<Particle>()
            private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            private var initialized = false

            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                if (!initialized && w > 0 && h > 0) {
                    initialized = true
                    val colors = listOf(0xFFBB86FC.toInt(), 0xFF03DAC6.toInt(), 0xFF7C4DFF.toInt(), 0xFFFFFFFF.toInt())
                    repeat(55) {
                        particles.add(Particle(
                            x = Random.nextFloat() * w,
                            y = Random.nextFloat() * h,
                            speed = Random.nextFloat() * 0.4f + 0.1f,
                            size = Random.nextFloat() * dp * 2.5f + dp * 0.5f,
                            alpha = Random.nextFloat() * 0.6f + 0.1f,
                            color = colors[Random.nextInt(colors.size)],
                            phase = Random.nextFloat() * (2 * Math.PI).toFloat()
                        ))
                    }
                }
            }

            override fun onDraw(canvas: Canvas) {
                val h = height.toFloat()
                val w = width.toFloat()
                val t = System.currentTimeMillis() / 1000f
                for (p in particles) {
                    p.y -= p.speed
                    p.x += sin((t + p.phase).toDouble()).toFloat() * 0.3f
                    if (p.y < -dp * 10) { p.y = h + dp * 5; p.x = Random.nextFloat() * w }
                    val twinkle = (sin((t * 2 + p.phase).toDouble()) * 0.3f + 0.7f).toFloat()
                    paint.color = p.color
                    paint.alpha = (p.alpha * twinkle * 255).toInt().coerceIn(0, 255)
                    canvas.drawCircle(p.x, p.y, p.size, paint)
                }
                postInvalidateOnAnimation()
            }
        }
    }

    private fun cancelAllAnimators() {
        activeAnimators.forEach { it.cancel() }
        activeAnimators.clear()
    }

    private fun removeLoadingScreen() {
        countdownTimer?.cancel()
        countdownTimer = null
        releaseAudioFocus()
        val view = overlayRoot ?: run { isLoadingScreenActive = false; return }
        view.animate().alpha(0f).setDuration(300)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try { windowManager?.removeView(view) } catch (_: Exception) {}
                    overlayRoot = null
                    isLoadingScreenActive = false
                }
            }).start()
    }

    // ─── Usage Warning (fires at WARNING_INTERVAL_MS) ─────────────────────────

    private fun startUsageTimer() {
        stopUsageTimer()
        scheduleNextWarning()
    }

    private fun scheduleNextWarning() {
        usageTimer = object : CountDownTimer(WARNING_INTERVAL_MS, 1000) {
            override fun onTick(millisUntilFinished: Long) {}
            override fun onFinish() {
                if (getTargetApps().contains(currentApp) && activeSessionApps.contains(currentApp)) {
                    showUsageWarning()
                }
            }
        }.start()
    }

    private fun stopUsageTimer() {
        usageTimer?.cancel()
        usageTimer = null
    }

    private fun showUsageWarning() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density

        val root = FrameLayout(this)

        // Semi-transparent dark background
        val bg = View(this).apply { setBackgroundColor(Color.parseColor("#D9000000")) }
        root.addView(bg, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        // Card
        val cardMargin = (dp * 28).toInt()
        val card = object : LinearLayout(this) {
            private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#1C1C2E")
            }
            private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.2f
                color = Color.parseColor("#55FF6B6B")
            }
            private val r = dp * 28f
            init {
                orientation = LinearLayout.VERTICAL
                gravity     = Gravity.CENTER_HORIZONTAL
                setPadding((dp * 32).toInt(), (dp * 36).toInt(), (dp * 32).toInt(), (dp * 36).toInt())
                setWillNotDraw(false)
            }
            override fun onDraw(canvas: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                canvas.drawRoundRect(rect, r, r, cardPaint)
                canvas.drawRoundRect(rect, r, r, strokePaint)
            }
        }

        val warningEmoji = TextView(this).apply {
            text = "⏰"; textSize = 52f; gravity = Gravity.CENTER
        }
        val warningTitle = TextView(this).apply {
            text = "Time's Up"
            setTextColor(Color.parseColor("#FF6B6B"))
            textSize = 26f; gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            setPadding(0, (dp * 16).toInt(), 0, 0)
        }
        val mins  = WARNING_INTERVAL_MS / 60_000
        val label = if (mins < 1) "${WARNING_INTERVAL_MS / 1000} seconds"
                    else "$mins minute${if (mins == 1L) "" else "s"}"
        val warningBody = TextView(this).apply {
            text = "You've spent $label here.\n\nIs this really worth your time?"
            setTextColor(Color.parseColor("#CCCCCC"))
            textSize = 15f; gravity = Gravity.CENTER
            setLineSpacing(0f, 1.5f)
            setPadding(0, (dp * 14).toInt(), 0, (dp * 28).toInt())
        }

        fun styledBtn(label: String, bgColor: Int, fgColor: Int): TextView =
            object : TextView(this) {
                private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = bgColor }
                private val r = dp * 16f
                init { setWillNotDraw(false) }
                override fun onDraw(c: Canvas) {
                    c.drawRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), r, r, p)
                    super.onDraw(c)
                }
            }.apply {
                text = label
                setTextColor(fgColor)
                textSize = 15f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding((dp * 24).toInt(), (dp * 18).toInt(), (dp * 24).toInt(), (dp * 18).toInt())
            }

        val goBackBtn = styledBtn("✓  I'll Do Something Better", Color.parseColor("#4CAF50"), Color.WHITE).apply {
            setOnClickListener {
                stopUsageTimer()
                activeSessionApps.remove(currentApp)
                currentApp = ""
                removeWarningOverlay()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }
        val continueBtn = styledBtn("Keep Going →", Color.parseColor("#1E1E30"), Color.parseColor("#9E9E9E")).apply {
            setOnClickListener {
                removeWarningOverlay()
                scheduleNextWarning()
            }
        }

        card.addView(warningEmoji)
        card.addView(warningTitle)
        card.addView(warningBody)
        card.addView(goBackBtn, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
        card.addView(View(this).apply { minimumHeight = (dp * 12).toInt() })
        card.addView(continueBtn, LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

        val cardLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
        cardLp.setMargins(cardMargin, 0, cardMargin, 0)
        root.addView(card, cardLp)

        val wParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        windowManager?.addView(root, wParams)
        warningRoot = root

        root.alpha = 0f
        root.animate().alpha(1f).setDuration(350).start()
    }

    private fun removeWarningOverlay() {
        val view = warningRoot ?: return
        view.animate().alpha(0f).setDuration(250)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try { windowManager?.removeView(view) } catch (_: Exception) {}
                    warningRoot = null
                }
            }).start()
    }

    // ─── Cleanup ──────────────────────────────────────────────────────────────

    override fun onInterrupt() {
        cancelAllAnimators()
        removeLoadingScreen()
        removeWarningOverlay()
        stopUsageTimer()
        releaseAudioFocus()
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelAllAnimators()
        removeLoadingScreen()
        removeWarningOverlay()
        stopUsageTimer()
        activeSessionApps.clear()
        releaseAudioFocus()
    }
}
