package com.yuvaan.lucid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.*

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
    private var isWarningScreenActive = false

    // Per-app counter for how many times the user has pressed "Continue for now"
    // Reset when the user leaves the target app
    private val continueCountMap = mutableMapOf<String, Int>()

    // Audio focus for pausing background playback
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    private fun getWarningIntervalMs(): Long {
        val lucidPrefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
        var mins = lucidPrefs.getInt("warning_interval_mins", -1)
        if (mins <= 0) {
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val flutterRaw = flutterPrefs.all["flutter.warning_interval_mins"]
            if (flutterRaw is Int && flutterRaw > 0) {
                mins = flutterRaw
            } else if (flutterRaw is Long && flutterRaw > 0) {
                mins = flutterRaw.toInt()
            }
        }
        if (mins <= 0) mins = 15
        return mins * 60 * 1000L
    }

    // Packages that must NEVER trigger the timer or be treated as "leaving" a target app.
    private val ignoredPackages = mutableSetOf(
        // System UI / Overlays / Screenshot
        "com.android.systemui",
        "com.miui.systemui",
        "com.miui.securitycenter",
        "com.miui.global.packageinstaller",
        "com.miui.screenshot",
        "com.miui.notification",
        "com.miui.statusbar",
        "com.samsung.android.app.cocktailbarservice",
        "com.samsung.android.quickpanel",
        "com.samsung.android.biometrics.app.setting",
        "com.samsung.android.sm.devicesecurity",
        "com.samsung.android.app.routine",
        "com.samsung.android.forest",
        "com.samsung.android.rubin.app",
        "com.samsung.android.incallui",
        "com.oplus.notification",
        "com.oplus.systemui",
        "com.oplus.qs",
        "com.google.android.gms",
        "com.google.android.googlequicksearchbox",
        // Common system overlays / permission dialogs
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "android"
    )

    private fun isIgnoredPackage(pkg: String, className: String?): Boolean {
        if (pkg == packageName) return true // ignore Lucid itself
        if (pkg == "android") return true   // ignore system server / audio

        val lowerPkg = pkg.lowercase()
        val lowerClass = className?.lowercase() ?: ""

        // Check package name substrings for common system UI / overlay / notification / keyboard / service patterns across all OEMs
        val systemUiSubstrings = listOf(
            "systemui", "notification", "controlcenter", "upslide", "quickpanel", "quicksettings",
            "statusbar", "shade", "volume", "sound", "audio", "media", "keyguard", "lockscreen", "lock",
            "screenshot", "screenrecorder", "capture", "permissioncontroller", "inputmethod", "honeyboard",
            "swiftkey", "cocktailbarservice", "assistantscreen", "assistant", "voice", "bixby",
            "floatassistant", "incallui", "aod", "overlay", "cleanoem", "edge", "sidegesture", "side",
            "battery", "powerkeeper", "cleaner", "guardprovider", "dialog", "alert", "popup", "floating",
            "packageinstaller", "smartclip", "sidegesturepad", "smartsuggestions", "biometrics", "fingerprint", "face",
            "smartshot", "aiservice", "touchtype", "iflytek", "sogou", "themecenter", "routine", "forest", "rubin",
            "gms", "googlequicksearchbox", "personalassistant", "appvault", "minusone", "freeform", "window",
            "securityadd", "cleanmaster", "discover", "mipicks", "clipboard", "taskedge", "appsedge", "clipboardedge",
            "sidegesturepad", "authframework", "smartsidebar", "trichromelibrary", "webview", "customtab",
            "autofill", "password", "credential", "safetycenter", "security", "guard", "cleaner", "power", "saver",
            "theme", "wallpaper", "icon", "widget", "plugin", "service", "provider", "server", "system", "framework",
            "android.gms", "android.gsf", "google.android.projection", "google.android.apps.tachyon",
            "google.android.as", "google.android.tts", "speech", "lens", "translate", "toast", "tooltip"
        )
        if (systemUiSubstrings.any { lowerPkg.contains(it) }) return true

        // Also ignore common system UI / dialog / keyboard / overlay / webview class names
        if (lowerClass.contains("inputmethod") || lowerClass.contains("statusbar") ||
            lowerClass.contains("notificationshade") || lowerClass.contains("volume") ||
            lowerClass.contains("systemui") || lowerClass.contains("quicksettings") ||
            lowerClass.contains("quickpanel") || lowerClass.contains("dialog") ||
            lowerClass.contains("popup") || lowerClass.contains("floating") ||
            lowerClass.contains("overlay") || lowerClass.contains("keyguard") ||
            lowerClass.contains("lockscreen") || lowerClass.contains("quickstep") ||
            lowerClass.contains("gesture") || lowerClass.contains("panel") ||
            lowerClass.contains("bar") || lowerClass.contains("menu") ||
            lowerClass.contains("drawer") || lowerClass.contains("sheet") ||
            lowerClass.contains("window") || lowerClass.contains("biometric") ||
            lowerClass.contains("fingerprint") || lowerClass.contains("face") ||
            lowerClass.contains("assistant") || lowerClass.contains("voice") ||
            lowerClass.contains("search") || lowerClass.contains("lens") ||
            lowerClass.contains("clipboard") || lowerClass.contains("edge") ||
            lowerClass.contains("side") || lowerClass.contains("toast") ||
            lowerClass.contains("tooltip") || lowerClass.contains("customtab") ||
            lowerClass.contains("webview")) {
            return true
        }

        val isLauncherOrRecentsPkg = pkg == "com.miui.recents" || pkg == "com.sec.android.app.taskmanager" ||
            lowerPkg.contains("recents") || lowerPkg.contains("overview") || lowerPkg.contains("taskbar") ||
            lowerPkg.contains("taskmanager") || lowerPkg.contains("launcher") || lowerPkg.contains("home") ||
            lowerPkg.contains("trebuchet") || lowerPkg.contains("quickstep")

        // ── If an active session is running (not on loading/warning screen) ──
        if (!isLoadingScreenActive && !isWarningScreenActive) {
            // Never ignore launcher or recents packages. This ensures that going to the home screen
            // or opening the recent apps menu properly ends the current session!
            if (isLauncherOrRecentsPkg) return false
            
            if (ignoredPackages.contains(pkg)) return true
        } else {
            // During loading screen / warning screen, do NOT ignore recents / taskmanager / launcher so leaving via gestures cancels the timer
            if (ignoredPackages.contains(pkg) && !isLauncherOrRecentsPkg) return true
        }

        return false
    }

    // ─── Target Apps ─────────────────────────────────────────────────────────

    private fun getTargetApps(): Set<String> {
        val lucidPrefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
        val lucidRaw = lucidPrefs.getString("target_apps", "") ?: ""
        val lucidSet = lucidRaw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val flutterRaw = flutterPrefs.getString("flutter.enabled_target_apps", "[]") ?: "[]"
        val flutterSet = flutterRaw
            .removePrefix("[").removeSuffix("]")
            .replace("\"", "")
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()

        return lucidSet + flutterSet
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        Log.d("Lucid", "Service connected")
    }

    // ─── Event Routing ────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val pkg = event.packageName?.toString() ?: return
        val className = event.className?.toString()

        // ── Always skip system UI, notification menu, recents, dialogs, keyboards ──
        // IMPORTANT: notification shade and recents are ignored here, so opening
        // or closing them does NOT update currentApp or end an active session.
        if (isIgnoredPackage(pkg, className)) return

        val targets = getTargetApps()

        // ── Skip duplicate same-package events (tab switches, dialogs, etc.) ─
        if (pkg == currentApp && currentApp.isNotEmpty()) {
            if (targets.contains(pkg)) {
                // If the user clicked "Leave" and reopened lightning fast, the package might never have changed to Home.
                // In that case, the session is dead (not in activeSessionApps) and no timer is shown.
                // We MUST start a new timer instead of skipping!
                if (activeSessionApps.contains(pkg) || isLoadingScreenActive || isWarningScreenActive) {
                    return
                }
            } else {
                return
            }
        }

        val prev = currentApp
        currentApp = pkg

        // ── Leaving a target app → only end session if going to a REAL non-target app ─
        if (prev.isNotEmpty() && targets.contains(prev) && !targets.contains(currentApp)) {
            activeSessionApps.remove(prev)
            continueCountMap.remove(prev)
            stopUsageTimer()
            if (isLoadingScreenActive || overlayRoot != null) {
                cancelAllAnimators()
                removeLoadingScreen()
            }
            Log.d("Lucid", "Left $prev → session ended (now at $currentApp)")
        }

        // ── Opened a target app ───────────────────────────────────────────────
        if (targets.contains(currentApp)) {
            if (activeSessionApps.contains(currentApp)) {
                // User returned to this app mid-session — no timer
                Log.d("Lucid", "Returned to $currentApp (active session) — no timer")
                return
            }
            if (!isLoadingScreenActive && !isWarningScreenActive) {
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

    // ─── Helper: Touch Scale Effect ───────────────────────────────────────────

    private fun View.addTouchScaleEffect(scaleDown: Float = 0.96f) {
        setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    v.animate().scaleX(scaleDown).scaleY(scaleDown).setDuration(120).start()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
                }
            }
            false
        }
    }

    // ─── Loading Screen ───────────────────────────────────────────────────────

    private fun showMindfulLoadingScreen() {
        if (overlayRoot != null) {
            try { windowManager?.removeView(overlayRoot) } catch (_: Exception) {}
            overlayRoot = null
        }
        isLoadingScreenActive = true

        // PAUSE the underlying app's audio immediately
        requestAudioFocus()

        val blockedApp = currentApp
        val totalMs    = 60_000L
        val dp         = resources.displayMetrics.density

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // Get app icon and label for personalized experience
        val appIcon: Drawable? = try { packageManager.getApplicationIcon(blockedApp) } catch (_: Exception) { null }
        val appLabel: String = try {
            val info = packageManager.getApplicationInfo(blockedApp, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { "This App" }

        // ── Root container with custom cosmic background & ambient glow ─────────
        val root = object : FrameLayout(this) {
            private val bgPaint = Paint().apply { color = Color.parseColor("#050510") }
            private val glowPaintTop = Paint(Paint.ANTI_ALIAS_FLAG)
            private val glowPaintBottom = Paint(Paint.ANTI_ALIAS_FLAG)
            
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                if (w > 0 && h > 0) {
                    glowPaintTop.shader = RadialGradient(
                        w * 0.2f, h * 0.2f, w * 0.8f,
                        intArrayOf(Color.parseColor("#25174B"), Color.parseColor("#0D0B1E"), Color.TRANSPARENT),
                        floatArrayOf(0f, 0.5f, 1f),
                        Shader.TileMode.CLAMP
                    )
                    glowPaintBottom.shader = RadialGradient(
                        w * 0.8f, h * 0.85f, w * 0.9f,
                        intArrayOf(Color.parseColor("#0E2A47"), Color.parseColor("#081426"), Color.TRANSPARENT),
                        floatArrayOf(0f, 0.5f, 1f),
                        Shader.TileMode.CLAMP
                    )
                }
            }

            override fun onDraw(canvas: Canvas) {
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgPaint)
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glowPaintTop)
                canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glowPaintBottom)
                super.onDraw(canvas)
            }
        }.apply {
            setWillNotDraw(false)
        }

        // ── Center content layout ─────────────────────────────────────────────
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity     = Gravity.CENTER_HORIZONTAL
            setPadding((dp * 24).toInt(), (dp * 36).toInt(), (dp * 24).toInt(), (dp * 36).toInt())
        }

        // ── App Title & Subtitle ──────────────────────────────────────────────
        val titleTv = TextView(this).apply {
            text = "Opening $appLabel"
            setTextColor(Color.WHITE)
            textSize = 24f
            gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            maxLines = 2
        }
        content.addView(titleTv, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        val subtitleTv = TextView(this).apply {
            text = "Take a conscious breath before you begin."
            setTextColor(Color.parseColor("#A1A1AA"))
            textSize = 13.5f
            gravity = Gravity.CENTER
            maxLines = 2
            setPadding(0, (dp * 6).toInt(), 0, (dp * 32).toInt())
        }
        content.addView(subtitleTv, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // ── Breathing Orb & Progress Arc ──────────────────────────────────────
        val orbSizePx = (dp * 260).toInt()
        var arcProgress = 1f
        var breathingScale = 1.0f

        val arcView = object : View(this) {
            private val auraPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 18
                color = Color.parseColor("#22BB86FC")
                strokeCap = Paint.Cap.ROUND
            }
            private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 8
                color = Color.parseColor("#1A1830")
                strokeCap = Paint.Cap.ROUND
            }
            private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 8
                strokeCap = Paint.Cap.ROUND
            }

            override fun onDraw(canvas: Canvas) {
                val cx = width / 2f
                val cy = height / 2f
                val pad = dp * 24
                val baseRect = RectF(pad, pad, width - pad, height - pad)

                // Breathing aura ring (scales with breathing pulse)
                canvas.save()
                canvas.scale(breathingScale, breathingScale, cx, cy)
                canvas.drawOval(baseRect, auraPaint)
                canvas.restore()

                // Track ring
                canvas.drawOval(baseRect, trackPaint)

                // Progress arc
                val sweep = arcProgress * 360f
                arcPaint.shader = SweepGradient(
                    cx, cy,
                    intArrayOf(
                        Color.parseColor("#F0ABFC"),
                        Color.parseColor("#C084FC"),
                        Color.parseColor("#38BDF8"),
                        Color.parseColor("#34D399"),
                        Color.parseColor("#F0ABFC")
                    ),
                    floatArrayOf(0f, 0.3f, 0.6f, 0.85f, 1f)
                )
                val matrix = Matrix()
                matrix.setRotate(-90f, cx, cy)
                arcPaint.shader.setLocalMatrix(matrix)
                canvas.drawArc(baseRect, -90f, sweep, false, arcPaint)
            }
        }

        // Center icon badge inside orb
        val iconSize = (dp * 84).toInt()
        val iconContainer = object : FrameLayout(this) {
            private val bgP = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#131124") }
            private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = dp * 2f; color = Color.parseColor("#3B3468")
            }
            init { setWillNotDraw(false) }
            override fun onDraw(c: Canvas) {
                val cx = width / 2f
                val cy = height / 2f
                val r = (width / 2f) - dp * 2
                c.drawCircle(cx, cy, r, bgP)
                c.drawCircle(cx, cy, r, strokeP)
                super.onDraw(c)
            }
        }
        
        val logoImage = ImageView(this).apply {
            if (appIcon != null) {
                setImageDrawable(appIcon)
            } else {
                setImageResource(R.mipmap.ic_launcher)
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        val iconPad = (dp * 16).toInt()
        iconContainer.addView(logoImage, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ).apply { setMargins(iconPad, iconPad, iconPad, iconPad) })

        val orbContainer = FrameLayout(this)
        orbContainer.addView(arcView, FrameLayout.LayoutParams(orbSizePx, orbSizePx, Gravity.CENTER))
        orbContainer.addView(iconContainer, FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER))

        content.addView(orbContainer, LinearLayout.LayoutParams(orbSizePx, orbSizePx).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })

        // ── Breathing Guidance & Seconds ──────────────────────────────────────
        val secondsTv = TextView(this).apply {
            text = "60"
            setTextColor(Color.WHITE)
            textSize = 52f
            gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            setPadding(0, (dp * 20).toInt(), 0, 0)
        }
        content.addView(secondsTv, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        val breathingGuidanceTv = TextView(this).apply {
            text = "Inhale slowly and deeply... 🌬️"
            setTextColor(Color.parseColor("#C4B5FD"))
            textSize = 13.5f
            gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            letterSpacing = 0.03f
            maxLines = 2
            setPadding(0, (dp * 6).toInt(), 0, 0)
        }
        content.addView(breathingGuidanceTv, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ))

        // ── Spacer ────────────────────────────────────────────────────────────
        content.addView(View(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (dp * 40).toInt()
        ))

        // ── Leave Button (Glassmorphic & Gradient) ────────────────────────────
        val goBackBtn = object : TextView(this) {
            private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#2A1225") }
            private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.5f
                color = Color.parseColor("#F43F5E")
            }
            private val cornerR = dp * 28f
            init { setWillNotDraw(false) }
            override fun onDraw(canvas: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                canvas.drawRoundRect(rect, cornerR, cornerR, bgPaint)
                canvas.drawRoundRect(rect, cornerR, cornerR, strokePaint)
                super.onDraw(canvas)
            }
        }.apply {
            text = "✨   Leave & Do Something Better"
            setTextColor(Color.parseColor("#FFE4E6"))
            textSize = 14.5f
            gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            maxLines = 1
              setPadding((dp * 16).toInt(), (dp * 18).toInt(), (dp * 16).toInt(), (dp * 18).toInt())
              addTouchScaleEffect(0.96f)
              setOnClickListener {
                  activeSessionApps.remove(currentApp)
                  continueCountMap.remove(currentApp)
                  cancelAllAnimators()
                  removeLoadingScreen()
                  performGlobalAction(GLOBAL_ACTION_HOME)
              }
          }
        content.addView(goBackBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins((dp * 8).toInt(), 0, (dp * 8).toInt(), 0) })

        // ── Wrap in centered layout ───────────────────────────────────────────
        val wrapper = FrameLayout(this)
        val wrapLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
        wrapper.addView(content, wrapLp)
        root.addView(wrapper, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // ── Window params ─────────────────────────────────────────────────────
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

        // Fade-in animation
        root.alpha = 0f
        root.animate().alpha(1f).setDuration(450).setInterpolator(android.view.animation.DecelerateInterpolator()).start()

        // ── Breathing Pulse Animator (4s Inhale, 4s Exhale) ───────────────────
        val breathAnimator = ValueAnimator.ofFloat(1.0f, 1.12f).apply {
            duration = 4000L
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener { anim ->
                breathingScale = anim.animatedValue as Float
                arcView.invalidate()
            }
        }
        breathAnimator.start()
        activeAnimators.add(breathAnimator)

        // ── Smooth Arc Progress Animator (for silky arc sweep) ────────────────
        val arcAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = totalMs
            interpolator = android.view.animation.LinearInterpolator()
            addUpdateListener { anim ->
                arcProgress = anim.animatedValue as Float
                arcView.invalidate()
            }
        }
        arcAnimator.start()
        activeAnimators.add(arcAnimator)

        // ── Countdown timer (text updates only — arc is handled by arcAnimator) ─
        val breathingMessages = arrayOf(
            "Inhale slowly and deeply... 🌬️",
            "Exhale and release tension... 🍃",
            "Notice how you feel right now... ✨",
            "Is this app what you truly need? 💭",
            "Inhale calm, exhale impulse... 🌊",
            "You are in control of your time... ⏳"
        )
        countdownTimer = object : CountDownTimer(totalMs, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                val secs = ((millisUntilFinished + 999) / 1000).coerceAtLeast(1)
                val elapsedSecs = ((totalMs - millisUntilFinished) / 1000).toInt()
                val msgIndex = (elapsedSecs / 10) % breathingMessages.size
                
                Handler(Looper.getMainLooper()).post {
                    secondsTv.text = "$secs"
                    breathingGuidanceTv.text = breathingMessages[msgIndex]
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

    private fun cancelAllAnimators() {
        activeAnimators.forEach { it.cancel() }
        activeAnimators.clear()
    }

    private fun removeLoadingScreen() {
        isLoadingScreenActive = false
        countdownTimer?.cancel()
        countdownTimer = null
        releaseAudioFocus()
        val view = overlayRoot ?: return
        view.animate().alpha(0f).setDuration(300)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try { windowManager?.removeView(view) } catch (_: Exception) {}
                    if (overlayRoot == view) {
                        overlayRoot = null
                    }
                }
            }).start()
    }

    // ─── Usage Warning (fires at WARNING_INTERVAL_MS) ─────────────────────────

    private fun startUsageTimer() {
        stopUsageTimer()
        scheduleNextWarning()
    }

    private fun scheduleNextWarning() {
        stopUsageTimer()
        val intervalMs = getWarningIntervalMs()
        usageTimer = object : CountDownTimer(intervalMs, 1000) {
            override fun onTick(millisUntilFinished: Long) {}
            override fun onFinish() {
                if (getTargetApps().contains(currentApp) && activeSessionApps.contains(currentApp)) {
                    Handler(Looper.getMainLooper()).post {
                        showUsageWarning()
                    }
                }
            }
        }.start()
    }

    private fun stopUsageTimer() {
        usageTimer?.cancel()
        usageTimer = null
    }

    private fun showUsageWarning() {
        if (isWarningScreenActive) return
        if (warningRoot != null) {
            try { windowManager?.removeView(warningRoot) } catch (_: Exception) {}
            warningRoot = null
        }
        isWarningScreenActive = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density

        val root = FrameLayout(this)

        // Semi-transparent backdrop with subtle purple/red ambient glow
        val bg = object : View(this) {
            private val bgP = Paint().apply { color = Color.parseColor("#E604040E") }
            private val glowP = Paint(Paint.ANTI_ALIAS_FLAG)
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                if (w > 0 && h > 0) {
                    glowP.shader = RadialGradient(
                        w / 2f, h / 2f, w * 0.6f,
                        intArrayOf(Color.parseColor("#3D1228"), Color.parseColor("#150A1A"), Color.TRANSPARENT),
                        floatArrayOf(0f, 0.6f, 1f),
                        Shader.TileMode.CLAMP
                    )
                }
            }
            override fun onDraw(c: Canvas) {
                c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bgP)
                c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glowP)
                super.onDraw(c)
            }
        }.apply { setWillNotDraw(false) }
        root.addView(bg, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        // Get app icon and label
        val appIcon: Drawable? = try { packageManager.getApplicationIcon(currentApp) } catch (_: Exception) { null }
        val appLabel: String = try {
            val info = packageManager.getApplicationInfo(currentApp, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { "This App" }

        // Card container
        val cardMargin = (dp * 24).toInt()
        val card = object : LinearLayout(this) {
            private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#15132A") }
            private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = dp * 1.5f
                color = Color.parseColor("#FF6B6B")
            }
            private val r = dp * 32f
            init {
                orientation = LinearLayout.VERTICAL
                gravity     = Gravity.CENTER_HORIZONTAL
                setPadding((dp * 28).toInt(), (dp * 36).toInt(), (dp * 28).toInt(), (dp * 32).toInt())
                setWillNotDraw(false)
            }
            override fun onDraw(canvas: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                canvas.drawRoundRect(rect, r, r, cardPaint)
                canvas.drawRoundRect(rect, r, r, strokePaint)
            }
        }

        // Header badge (App Icon or Clock)
        val badgeSize = (dp * 76).toInt()
        val badgeContainer = object : FrameLayout(this) {
            private val bgP = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#2D152A") }
            private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = dp * 2f; color = Color.parseColor("#FF6B6B")
            }
            init { setWillNotDraw(false) }
            override fun onDraw(c: Canvas) {
                val cx = width / 2f
                val cy = height / 2f
                val r = (width / 2f) - dp * 2
                c.drawCircle(cx, cy, r, bgP)
                c.drawCircle(cx, cy, r, strokeP)
                super.onDraw(c)
            }
        }
        val badgeImage = ImageView(this).apply {
            if (appIcon != null) {
                setImageDrawable(appIcon)
            } else {
                setImageResource(R.mipmap.ic_launcher)
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        val badgePad = (dp * 16).toInt()
        badgeContainer.addView(badgeImage, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT
        ).apply { setMargins(badgePad, badgePad, badgePad, badgePad) })

        card.addView(badgeContainer, LinearLayout.LayoutParams(badgeSize, badgeSize).apply {
            bottomMargin = (dp * 20).toInt()
        })

        // Title
        val warningTitle = TextView(this).apply {
            text = "Mindful Check-in"
            setTextColor(Color.WHITE)
            textSize = 24f; gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
        }
        card.addView(warningTitle)

        // Time spent pill
        val intervalMs = getWarningIntervalMs()
        val mins  = intervalMs / 60_000
        val label = if (mins < 1) "${intervalMs / 1000} seconds"
                    else "$mins minute${if (mins == 1L) "" else "s"}"

        val timePill = object : TextView(this) {
            private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#2A183D") }
            private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = dp * 1f; color = Color.parseColor("#5A2E7A")
            }
            private val r = dp * 20f
            init { setWillNotDraw(false) }
            override fun onDraw(c: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                c.drawRoundRect(rect, r, r, p)
                c.drawRoundRect(rect, r, r, strokeP)
                super.onDraw(c)
            }
        }.apply {
            text = "⏳   You've spent $label in $appLabel"
            setTextColor(Color.parseColor("#F0ABFC"))
            textSize = 13f; gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            setPadding((dp * 16).toInt(), (dp * 8).toInt(), (dp * 16).toInt(), (dp * 8).toInt())
        }
        card.addView(timePill, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins(0, (dp * 16).toInt(), 0, (dp * 20).toInt()) })

        // Thought-provoking body
        val warningBody = TextView(this).apply {
            text = "Time is your most valuable resource.\n\nTaking a pause now can help you regain focus and intention. Is continuing right now aligned with what you want to achieve today?"
            setTextColor(Color.parseColor("#CBD5E1"))
            textSize = 15f; gravity = Gravity.CENTER
            setLineSpacing(0f, 1.4f)
            setPadding(0, 0, 0, (dp * 32).toInt())
        }
        card.addView(warningBody)

        // Primary Action Button (Mint / Emerald)
        val goBackBtn = object : TextView(this) {
            private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#059669") }
            private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE; strokeWidth = dp * 1.5f; color = Color.parseColor("#34D399")
            }
            private val r = dp * 24f
            init { setWillNotDraw(false) }
            override fun onDraw(c: Canvas) {
                val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                c.drawRoundRect(rect, r, r, p)
                c.drawRoundRect(rect, r, r, strokeP)
                super.onDraw(c)
            }
        }.apply {
            text = "✓   Yes, Let's Take a Break"
            setTextColor(Color.WHITE)
            textSize = 16f; gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
              setPadding((dp * 24).toInt(), (dp * 16).toInt(), (dp * 24).toInt(), (dp * 16).toInt())
              addTouchScaleEffect(0.96f)
              setOnClickListener {
                  activeSessionApps.remove(currentApp)
                  continueCountMap.remove(currentApp)
                  stopUsageTimer()
                  removeWarningOverlay()
                  performGlobalAction(GLOBAL_ACTION_HOME)
              }
          }
        card.addView(goBackBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = (dp * 12).toInt() })

        // Secondary Action Button (Ghost / Dark) — only shown on first warning per session
        val appContinueCount = continueCountMap.getOrDefault(currentApp, 0)
        if (appContinueCount < 1) {
            val continueBtn = object : TextView(this) {
                private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#1F1C36") }
                private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = dp * 1f; color = Color.parseColor("#3E3960")
                }
                private val r = dp * 24f
                init { setWillNotDraw(false) }
                override fun onDraw(c: Canvas) {
                    val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                    c.drawRoundRect(rect, r, r, p)
                    c.drawRoundRect(rect, r, r, strokeP)
                    super.onDraw(c)
                }
            }.apply {
                text = "Continue for now →"
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 14f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding((dp * 20).toInt(), (dp * 14).toInt(), (dp * 20).toInt(), (dp * 14).toInt())
                addTouchScaleEffect(0.97f)
                setOnClickListener {
                    continueCountMap[currentApp] = appContinueCount + 1
                    removeWarningOverlay()
                    scheduleNextWarning()
                }
            }
            card.addView(continueBtn, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ))
        }

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
        isWarningScreenActive = false
        val view = warningRoot ?: return
        view.animate().alpha(0f).setDuration(250)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    try { windowManager?.removeView(view) } catch (_: Exception) {}
                    if (warningRoot == view) {
                        warningRoot = null
                    }
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
        continueCountMap.clear()
        releaseAudioFocus()
    }
}
