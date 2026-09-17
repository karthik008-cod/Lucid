package com.yuvaan.lucid

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.*
import android.graphics.drawable.Drawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.*

class LucidAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var isServiceRunning: Boolean = false
            private set
        @Volatile
        var lastHeartbeatMs: Long = 0L
            private set
    }

    //  State 

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

    // System Event Receiver for Screen Off and Incoming Calls
    private var systemEventReceiver: BroadcastReceiver? = null
    private var isSystemReceiverRegistered = false

    // Daily Limit Tracking
    private lateinit var dailyLimitManager: DailyLimitManager

    // Service health heartbeat
    private val healthCheckHandler = Handler(Looper.getMainLooper())
    private val healthCheckRunnable = object : Runnable {
        override fun run() {
            try {
                lastHeartbeatMs = System.currentTimeMillis()
                Log.d("Lucid", "Heartbeat: alive=true, currentApp='$currentApp', activeSessions=$activeSessionApps, loadingActive=$isLoadingScreenActive, warningActive=$isWarningScreenActive")
            } catch (e: Exception) {
                Log.e("Lucid", "Error in heartbeat", e)
            }
            healthCheckHandler.postDelayed(this, 30000)
        }
    }

    private fun parseMins(raw: Any?): Int {
        return when (raw) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull() ?: -1
            else -> -1
        }
    }

    private fun getWarningIntervalMs(): Long {
        return try {
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lucidPrefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
            var mins = -1

            // 1. Try individual app timer first (both Flutter and Lucid prefs)
            if (currentApp.isNotEmpty()) {
                val rawApp = flutterPrefs.all["flutter.app_timer_$currentApp"]
                    ?: lucidPrefs.all["app_timer_$currentApp"]
                val parsed = parseMins(rawApp)
                if (parsed > 0) {
                    mins = parsed
                    Log.d("Lucid", "Found per-app timer for $currentApp: $mins mins")
                }
            }

            // 2. Fall back to global warning timer if individual is not set
            if (mins <= 0) {
                val rawLucid = lucidPrefs.all["warning_interval_mins"]
                mins = parseMins(rawLucid)
            }
            if (mins <= 0) {
                val rawFlutter = flutterPrefs.all["flutter.warning_interval_mins"]
                mins = parseMins(rawFlutter)
            }

            if (mins <= 0) {
                mins = 15
                Log.d("Lucid", "Using default warning interval: 15 mins")
            } else {
                Log.d("Lucid", "Resolved warning interval for $currentApp: $mins mins")
            }

            mins * 60 * 1000L
        } catch (e: Exception) {
            Log.e("Lucid", "Error calculating warning interval, defaulting to 15 mins", e)
            15 * 60 * 1000L
        }
    }

    // Packages that must NEVER trigger the timer or be treated as "leaving" a target app.
    private val ignoredPackages = setOf(
        // System UI / Overlays / Screenshot / Status Bar / Quick Settings
        "com.android.systemui",
        "com.miui.systemui",
        "com.miui.securitycenter",
        "com.miui.global.packageinstaller",
        "com.miui.screenshot",
        "com.miui.notification",
        "com.miui.statusbar",
        "com.miui.screenrecorder",
        "com.miui.powerkeeper",
        "com.miui.securityadd",
        "com.miui.cleanmaster",
        "com.xiaomi.misettings",
        "com.samsung.android.app.cocktailbarservice",
        "com.samsung.android.quickpanel",
        "com.samsung.android.biometrics.app.setting",
        "com.samsung.android.sm.devicesecurity",
        "com.samsung.android.incallui",
        "com.oplus.notification",
        "com.oplus.systemui",
        "com.oplus.qs",
        "com.oplus.screenrecorder",
        // Audio / Volume / Sound overlays
        "com.miui.audio",
        "com.xiaomi.audio",
        "com.miui.voiceassist",
        "com.miui.soundrecorder",
        "com.google.android.soundpicker",
        "com.sec.android.app.soundalive",
        "com.samsung.android.soundassistant",
        // Telephony / In-Call UI
        "com.android.server.telecom",
        "com.android.phone",
        "com.android.incallui",
        "com.google.android.dialer",
        // Common Input Methods (keyboards)
        "com.google.android.inputmethod.latin",
        "com.samsung.android.honeyboard",
        "com.touchtype.swiftkey",
        // Common system overlays / permission dialogs
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.google.android.gms"
    )

    private fun isIgnoredPackage(pkg: String, className: String?): Boolean {
        if (pkg == packageName) return true // ignore Lucid itself
        if (pkg == "android") return true   // ignore system server / framework

        if (ignoredPackages.contains(pkg)) return true

        val lowerPkg = pkg.lowercase()
        val lowerClass = className?.lowercase() ?: ""

        // 1. Input methods / Keyboards
        if (lowerPkg.contains("inputmethod") || lowerPkg.contains("keyboard")) return true

        // 2. Volume, Sound, Audio dialogs & sliders (Fix for volume button press glitch)
        if (lowerPkg.contains("volume") || lowerPkg.contains("sound") || lowerPkg.contains("audio") ||
            lowerClass.contains("volume") || lowerClass.contains("volumedialog") ||
            lowerClass.contains("sound") || lowerClass.contains("audio")) {
            return true
        }

        // 3. System UI: Status Bar, Quick Settings, Brightness, Notifications, Heads-up banners
        if (lowerPkg.contains("systemui") || lowerPkg.contains("notification") ||
            lowerClass.contains("quicksettings") || lowerClass.contains("brightness") ||
            lowerClass.contains("headsup") || lowerClass.contains("heads_up") ||
            lowerClass.contains("statusbar") || lowerClass.contains("pip") ||
            lowerClass.contains("pictureinpicture")) {
            return true
        }

        // 4. Power Dialog, Global Actions, Shutdown dialogs
        if (lowerClass.contains("globalactions") || lowerClass.contains("powerdialog") ||
            lowerClass.contains("shutdown") || lowerClass.contains("reboot")) {
            return true
        }

        // 5. Screenshot & Screen Recorder toolbars/previews
        if (lowerPkg.contains("screenshot") || lowerClass.contains("screenshot") ||
            lowerPkg.contains("screenrecorder") || lowerClass.contains("screenrecorder")) {
            return true
        }

        // 6. Biometric, Fingerprint, Face Unlock prompts
        if (lowerPkg.contains("biometric") || lowerClass.contains("biometric") ||
            lowerClass.contains("fingerprint") || lowerClass.contains("faceunlock")) {
            return true
        }

        // 7. Clipboard, Autofill, and Password Manager popups
        if (lowerPkg.contains("autofill") || lowerClass.contains("autofill") ||
            lowerClass.contains("clipboard") || lowerPkg.contains("clipboard")) {
            return true
        }

        // 8. Voice Assistants, Floating bubbles, Edge panels, Game Turbo overlays
        if (lowerPkg.contains("gameturbo") || lowerClass.contains("gamebooster") ||
            lowerClass.contains("edgepanel") || lowerPkg.contains("floating") ||
            lowerClass.contains("floating") || lowerPkg.contains("voiceassist")) {
            return true
        }

        // 9. Generic Toast and transient popup windows
        if (lowerClass.contains("toast") || lowerClass.contains("transientnotification")) {
            return true
        }

        return false
    }

    private fun isLauncherOrRecent(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        val lower = pkg.lowercase()
        if (lower.contains("launcher") || lower.contains("home") || lower.contains("recents") || lower.contains("overview")) return true
        return try {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
            val resolveInfo = packageManager.resolveActivity(homeIntent, PackageManager.MATCH_DEFAULT_ONLY)
            resolveInfo?.activityInfo?.packageName == pkg
        } catch (_: Exception) {
            false
        }
    }

    private fun isRealUserApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        if (isLauncherOrRecent(pkg)) return true
        return try {
            packageManager.getLaunchIntentForPackage(pkg) != null
        } catch (_: Exception) {
            false
        }
    }

    //  Target Apps 

    private fun getTargetApps(): Set<String> {
        return try {
            val lucidPrefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
            val lucidRaw = try { lucidPrefs.getString("target_apps", "") ?: "" } catch (_: Exception) { "" }
            val lucidSet = lucidRaw.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()

            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val rawFlutter = flutterPrefs.all["flutter.enabled_target_apps"]
            val flutterSet = when (rawFlutter) {
                is String -> {
                    rawFlutter
                        .removePrefix("[").removeSuffix("]")
                        .replace("\"", "")
                        .split(",")
                        .map { it.trim() }
                        .filter { it.isNotEmpty() }
                        .toSet()
                }
                is Set<*> -> {
                    rawFlutter.filterIsInstance<String>().toSet()
                }
                is List<*> -> {
                    rawFlutter.filterIsInstance<String>().toSet()
                }
                else -> emptySet()
            }

            lucidSet + flutterSet
        } catch (e: Exception) {
            Log.e("Lucid", "Error getting target apps", e)
            emptySet()
        }
    }

    private fun startForegroundServiceIfNeeded() {
        try {
            val channelId = "lucid_guard_channel"
            val channelName = "Lucid Protection Status"
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm != null) {
                val channel = NotificationChannel(
                    channelId,
                    channelName,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Protects Lucid accessibility engine from OEM battery optimization"
                    setShowBadge(false)
                }
                nm.createNotificationChannel(channel)
            }

            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val pendingIntent = if (launchIntent != null) {
                PendingIntent.getActivity(
                    this, 0, launchIntent,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    else PendingIntent.FLAG_UPDATE_CURRENT
                )
            } else null

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notification = builder
                .setContentTitle("Lucid is protecting your focus")
                .setContentText("Mindful screen time engine is active")
                .setSmallIcon(R.mipmap.ic_launcher)
                .apply {
                    if (pendingIntent != null) setContentIntent(pendingIntent)
                }
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                } else {
                    startForeground(1001, notification)
                }
            } else {
                startForeground(1001, notification)
            }
            Log.d("Lucid", "Foreground service started with persistent notification (SmartPower immune)")
        } catch (e: Exception) {
            Log.e("Lucid", "Error starting foreground notification", e)
        }
    }

    private fun registerSystemReceiver() {
        if (isSystemReceiverRegistered) return
        try {
            systemEventReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    val action = intent?.action ?: return
                    when (action) {
                        Intent.ACTION_SCREEN_OFF -> {
                            Log.d("Lucid", "Screen turned off — canceling active timers to avoid pocket ticks")
                            if (isLoadingScreenActive || overlayRoot != null) {
                                cancelAllAnimators()
                                removeLoadingScreen()
                                releaseAudioFocus()
                            }
                            if (isWarningScreenActive || warningRoot != null) {
                                removeWarningOverlay()
                            }
                        }
                        TelephonyManager.ACTION_PHONE_STATE_CHANGED -> {
                            val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
                            if (state == TelephonyManager.EXTRA_STATE_RINGING || state == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                                Log.d("Lucid", "Incoming/active call ($state) — yielding overlay and releasing audio focus")
                                releaseAudioFocus()
                                if (isLoadingScreenActive || overlayRoot != null) {
                                    cancelAllAnimators()
                                    removeLoadingScreen()
                                }
                                if (isWarningScreenActive || warningRoot != null) {
                                    removeWarningOverlay()
                                }
                            }
                        }
                    }
                }
            }
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
            }
            registerReceiver(systemEventReceiver, filter)
            isSystemReceiverRegistered = true
            Log.d("Lucid", "System event receiver registered")
        } catch (e: Exception) {
            Log.e("Lucid", "Error registering system event receiver", e)
        }
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        try {
            isServiceRunning = true
            lastHeartbeatMs = System.currentTimeMillis()
            audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            dailyLimitManager = DailyLimitManager(this)
            startForegroundServiceIfNeeded()
            registerSystemReceiver()
            Log.d("Lucid", "LucidAccessibilityService created")
        } catch (e: Exception) {
            Log.e("Lucid", "Error in onCreate", e)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        try {
            isServiceRunning = true
            lastHeartbeatMs = System.currentTimeMillis()
            if (audioManager == null) audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (windowManager == null) windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            if (!::dailyLimitManager.isInitialized) dailyLimitManager = DailyLimitManager(this)
            startForegroundServiceIfNeeded()
            registerSystemReceiver()
            healthCheckHandler.removeCallbacks(healthCheckRunnable)
            healthCheckHandler.postDelayed(healthCheckRunnable, 5000)
            Log.d("Lucid", "Service connected successfully")
        } catch (e: Exception) {
            Log.e("Lucid", "Error in onServiceConnected", e)
        }
    }

    // ─── Event Routing ────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        try {
            isServiceRunning = true
            lastHeartbeatMs = System.currentTimeMillis()
            if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

            val pkg = event.packageName?.toString() ?: return
            val className = event.className?.toString()

            // Always skip system UI, volume/sound sliders, notification shade, dialogs, keyboards
            if (isIgnoredPackage(pkg, className)) return

            val targets = getTargetApps()

            // Shield active overlays (60s pause, warning, or daily limit screen)
            // against transient non-app events or internal sub-panels
            val hasActiveOverlay = isLoadingScreenActive || isWarningScreenActive ||
                (::dailyLimitManager.isInitialized && dailyLimitManager.isShowingLimitScreen())

            if (hasActiveOverlay) {
                // Same app sub-event (e.g. video player view, tab, internal dialog) -> keep overlay active
                if (pkg == currentApp) return

                // Switching directly to another monitored target app -> transition gracefully
                if (targets.contains(pkg)) {
                    Log.d("Lucid", "Switching from $currentApp to another target app: $pkg")
                    cancelAllAnimators()
                    removeLoadingScreen()
                    removeWarningOverlay()
                    if (::dailyLimitManager.isInitialized) {
                        dailyLimitManager.removeScreen()
                        dailyLimitManager.recordSessionEnd(currentApp)
                    }
                    currentApp = pkg
                    if (::dailyLimitManager.isInitialized && dailyLimitManager.hasExceededDailyLimit(pkg)) {
                        dailyLimitManager.showDailyLimitScreen(pkg) {
                            activeSessionApps.remove(pkg)
                            continueCountMap.remove(pkg)
                            dailyLimitManager.recordSessionEnd(pkg)
                            performGlobalAction(GLOBAL_ACTION_HOME)
                        }
                    } else {
                        if (::dailyLimitManager.isInitialized) {
                            dailyLimitManager.recordSessionStart(pkg)
                        }
                        showMindfulLoadingScreen()
                    }
                    return
                }

                // If event is NOT a real user/launcher app (e.g. transient dialog, floating tool, OEM overlay):
                // SHIELD THE TIMER: do NOT remove the loading screen or drop session!
                if (!isRealUserApp(pkg)) {
                    Log.d("Lucid", "Shielding active timer against transient non-user app: $pkg ($className)")
                    return
                }

                // User genuinely navigated to Home/Recents or another real user app (e.g. WhatsApp):
                Log.d("Lucid", "User genuinely navigated away during active timer to: $pkg ($className)")
                activeSessionApps.remove(currentApp)
                continueCountMap.remove(currentApp)
                stopUsageTimer()
                cancelAllAnimators()
                removeLoadingScreen()
                removeWarningOverlay()
                releaseAudioFocus()
                if (::dailyLimitManager.isInitialized) {
                    dailyLimitManager.recordSessionEnd(currentApp)
                    dailyLimitManager.removeScreen()
                }
                currentApp = pkg
                return
            }

            if (pkg != currentApp) {
                Log.d("Lucid", "Event: app switch '$currentApp' -> '$pkg' (class: $className)")
            }

            // Skip duplicate same-package events (tab switches, dialogs, etc.)
            if (pkg == currentApp && currentApp.isNotEmpty()) {
                if (targets.contains(pkg)) {
                    // If the user clicked "Leave" and reopened lightning fast, session is dead
                    if (activeSessionApps.contains(pkg) || isLoadingScreenActive || isWarningScreenActive) {
                        return
                    }
                } else {
                    return
                }
            }

            val prev = currentApp
            currentApp = pkg

            // Leaving a target app — only end session if going to a REAL non-target app
            if (prev.isNotEmpty() && targets.contains(prev) && !targets.contains(currentApp)) {
                if (!isRealUserApp(currentApp)) {
                    // Not a real app switch, don't end session
                    currentApp = prev
                    return
                }
                activeSessionApps.remove(prev)
                continueCountMap.remove(prev)
                stopUsageTimer()
                if (::dailyLimitManager.isInitialized) {
                    dailyLimitManager.recordSessionEnd(prev)
                }
                if (isLoadingScreenActive || overlayRoot != null) {
                    cancelAllAnimators()
                    removeLoadingScreen()
                }
                if (isWarningScreenActive || warningRoot != null) {
                    removeWarningOverlay()
                }
                if (::dailyLimitManager.isInitialized && dailyLimitManager.isShowingLimitScreen()) {
                    dailyLimitManager.removeScreen()
                }
                Log.d("Lucid", "Left $prev — session ended (now at $currentApp)")
            }

            // Opened a target app
            if (targets.contains(currentApp)) {
                if (activeSessionApps.contains(currentApp)) {
                    Log.d("Lucid", "Returned to $currentApp (active session) — no timer")
                    return
                }
                if (!isLoadingScreenActive && !isWarningScreenActive &&
                    !(::dailyLimitManager.isInitialized && dailyLimitManager.isShowingLimitScreen())) {
                    stopUsageTimer()

                    if (::dailyLimitManager.isInitialized && dailyLimitManager.hasExceededDailyLimit(currentApp)) {
                        Log.d("Lucid", "$currentApp exceeded daily limit, showing daily limit screen")
                        dailyLimitManager.showDailyLimitScreen(currentApp) {
                            activeSessionApps.remove(currentApp)
                            continueCountMap.remove(currentApp)
                            dailyLimitManager.recordSessionEnd(currentApp)
                            performGlobalAction(GLOBAL_ACTION_HOME)
                        }
                    } else {
                        if (::dailyLimitManager.isInitialized) {
                            dailyLimitManager.recordSessionStart(currentApp)
                        }
                        Log.d("Lucid", "Showing mindful loading screen for $currentApp")
                        showMindfulLoadingScreen()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("Lucid", "Error in onAccessibilityEvent", e)
        }
    }

    //  Audio Focus (pauses background audio) 

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

    //  Helper: Touch Scale Effect 

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

    //  Loading Screen 

    private fun showMindfulLoadingScreen() {
      try {
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

        if (windowManager == null) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        }

        // Get app icon and label for personalized experience
        val appIcon: Drawable? = try { packageManager.getApplicationIcon(blockedApp) } catch (_: Exception) { null }
        val appLabel: String = try {
            val info = packageManager.getApplicationInfo(blockedApp, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { "This App" }

        //  Root container with custom cosmic background & ambient glow 
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

            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                    try {
                        cancelAllAnimators()
                        removeLoadingScreen()
                        releaseAudioFocus()
                        if (::dailyLimitManager.isInitialized) {
                            dailyLimitManager.recordSessionEnd(currentApp)
                        }
                        performGlobalAction(GLOBAL_ACTION_HOME)
                    } catch (e: Exception) {
                        Log.e("Lucid", "Error handling back key on loading screen", e)
                    }
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }.apply {
            setWillNotDraw(false)
            isFocusableInTouchMode = true
            requestFocus()
        }

        //  Center content layout 
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity     = Gravity.CENTER_HORIZONTAL
            setPadding((dp * 24).toInt(), (dp * 36).toInt(), (dp * 24).toInt(), (dp * 36).toInt())
        }

        //  App Title & Subtitle 
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

        //  Breathing Orb & Progress Arc 
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

        //  Breathing Guidance & Seconds 
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
            text = "Inhale slowly and deeply... "
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

        //  Spacer 
        content.addView(View(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (dp * 40).toInt()
        ))

        //  Leave Button (Glassmorphic & Gradient) 
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
            text = "   Leave & Do Something Better"
            setTextColor(Color.parseColor("#FFE4E6"))
            textSize = 14.5f
            gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
            maxLines = 1
              setPadding((dp * 16).toInt(), (dp * 18).toInt(), (dp * 16).toInt(), (dp * 18).toInt())
              addTouchScaleEffect(0.96f)
              setOnClickListener {
                  try {
                      activeSessionApps.remove(currentApp)
                      continueCountMap.remove(currentApp)
                      cancelAllAnimators()
                      removeLoadingScreen()
                      if (::dailyLimitManager.isInitialized) {
                          dailyLimitManager.recordSessionEnd(currentApp)
                      }
                      performGlobalAction(GLOBAL_ACTION_HOME)
                  } catch (e: Exception) {
                      Log.e("Lucid", "Error leaving from loading screen", e)
                  }
              }
          }
        content.addView(goBackBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins((dp * 8).toInt(), 0, (dp * 8).toInt(), 0) })

        //  Wrap in centered layout 
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

        //  Window params 
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        try {
            windowManager?.addView(root, params)
            overlayRoot = root
        } catch (e: Exception) {
            Log.e("Lucid", "Error adding loading screen overlay", e)
            isLoadingScreenActive = false
            return
        }

        // Fade-in animation
        root.alpha = 0f
        root.animate().alpha(1f).setDuration(450).setInterpolator(android.view.animation.DecelerateInterpolator()).start()

        //  Breathing Pulse Animator (4s Inhale, 4s Exhale) 
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

        //  Smooth Arc Progress Animator (for silky arc sweep) 
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

        //  Countdown timer (text updates only  arc is handled by arcAnimator) 
        val breathingMessages = arrayOf(
            "Inhale slowly and deeply... ",
            "Exhale and release tension... ",
            "Notice how you feel right now... ",
            "Is this app what you truly need? ",
            "Inhale calm, exhale impulse... ",
            "You are in control of your time... "
        )
        countdownTimer = object : CountDownTimer(totalMs, 1000) {
            override fun onTick(millisUntilFinished: Long) {
                try {
                    val secs = ((millisUntilFinished + 999) / 1000).coerceAtLeast(1)
                    val elapsedSecs = ((totalMs - millisUntilFinished) / 1000).toInt()
                    val msgIndex = (elapsedSecs / 10) % breathingMessages.size
                    
                    Handler(Looper.getMainLooper()).post {
                        try {
                            if (!isLoadingScreenActive || overlayRoot == null) return@post
                            secondsTv.text = "$secs"
                            breathingGuidanceTv.text = breathingMessages[msgIndex]
                        } catch (e: Exception) {
                            Log.e("Lucid", "Error updating countdown UI", e)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("Lucid", "Error in countdownTimer onTick", e)
                }
            }
            override fun onFinish() {
                try {
                    cancelAllAnimators()
                    activeSessionApps.add(blockedApp)
                    releaseAudioFocus()
                    removeLoadingScreen()
                    startUsageTimer()
                } catch (e: Exception) {
                    Log.e("Lucid", "Error in countdownTimer onFinish", e)
                }
            }
        }.start()
      } catch (e: Exception) {
          Log.e("Lucid", "Error showing loading screen", e)
          isLoadingScreenActive = false
      }
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
        try {
            view.animate().alpha(0f).setDuration(300)
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        try { windowManager?.removeView(view) } catch (_: Exception) {}
                        if (overlayRoot == view) {
                            overlayRoot = null
                        }
                    }
                }).start()
        } catch (e: Exception) {
            Log.e("Lucid", "Error removing loading screen", e)
            try { windowManager?.removeView(view) } catch (_: Exception) {}
            overlayRoot = null
        }
    }

    //  Usage Warning (fires at WARNING_INTERVAL_MS) 

    private fun startUsageTimer() {
        stopUsageTimer()
        scheduleNextWarning()
    }

    private fun scheduleNextWarning() {
        try {
            stopUsageTimer()
            val intervalMs = getWarningIntervalMs()
            Log.d("Lucid", "Scheduling next warning in ${intervalMs / 1000}s for $currentApp")
            usageTimer = object : CountDownTimer(intervalMs, 1000) {
                override fun onTick(millisUntilFinished: Long) {}
                override fun onFinish() {
                    try {
                        Log.d("Lucid", "Usage timer finished for $currentApp. Active session: ${activeSessionApps.contains(currentApp)}")
                        if (getTargetApps().contains(currentApp) && activeSessionApps.contains(currentApp)) {
                            Handler(Looper.getMainLooper()).post {
                                try {
                                    showUsageWarning()
                                } catch (e: Exception) {
                                    Log.e("Lucid", "Error showing warning in post", e)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("Lucid", "Error in usage timer finish", e)
                    }
                }
            }.start()
        } catch (e: Exception) {
            Log.e("Lucid", "Error in scheduleNextWarning", e)
        }
    }

    private fun stopUsageTimer() {
        usageTimer?.cancel()
        usageTimer = null
    }

    private fun showUsageWarning() {
      try {
        if (isWarningScreenActive) return
        if (warningRoot != null) {
            try { windowManager?.removeView(warningRoot) } catch (_: Exception) {}
            warningRoot = null
        }
        isWarningScreenActive = true
        if (windowManager == null) {
            windowManager = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        }
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
            text = "   You've spent $label in $appLabel"
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
            text = "   Yes, Let's Take a Break"
            setTextColor(Color.WHITE)
            textSize = 16f; gravity = Gravity.CENTER
            setTypeface(Typeface.DEFAULT_BOLD)
              setPadding((dp * 24).toInt(), (dp * 16).toInt(), (dp * 24).toInt(), (dp * 16).toInt())
              addTouchScaleEffect(0.96f)
              setOnClickListener {
                  try {
                      activeSessionApps.remove(currentApp)
                      continueCountMap.remove(currentApp)
                      stopUsageTimer()
                      removeWarningOverlay()
                      if (::dailyLimitManager.isInitialized) {
                          dailyLimitManager.recordSessionEnd(currentApp)
                      }
                      performGlobalAction(GLOBAL_ACTION_HOME)
                  } catch (e: Exception) {
                      Log.e("Lucid", "Error on warning goBack click", e)
                  }
              }
          }
        card.addView(goBackBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = (dp * 12).toInt() })

        // Secondary Action Button (Ghost / Dark)  only shown on first warning per session
        val appContinueCount = continueCountMap[currentApp] ?: 0
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
                text = "Continue for now "
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 14f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding((dp * 20).toInt(), (dp * 14).toInt(), (dp * 20).toInt(), (dp * 14).toInt())
                addTouchScaleEffect(0.97f)
                setOnClickListener {
                    try {
                        continueCountMap[currentApp] = appContinueCount + 1
                        removeWarningOverlay()
                        scheduleNextWarning()
                    } catch (e: Exception) {
                        Log.e("Lucid", "Error on continue click", e)
                    }
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
        try {
            windowManager?.addView(root, wParams)
            warningRoot = root
        } catch (e: Exception) {
            Log.e("Lucid", "Error adding warning overlay", e)
            isWarningScreenActive = false
            return
        }

        root.alpha = 0f
        root.animate().alpha(1f).setDuration(350).start()
      } catch (e: Exception) {
          Log.e("Lucid", "Error showing usage warning", e)
          isWarningScreenActive = false
      }
    }

    private fun removeWarningOverlay() {
        isWarningScreenActive = false
        val view = warningRoot ?: return
        try {
            view.animate().alpha(0f).setDuration(250)
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        try { windowManager?.removeView(view) } catch (_: Exception) {}
                        if (warningRoot == view) {
                            warningRoot = null
                        }
                    }
                }).start()
        } catch (e: Exception) {
            Log.e("Lucid", "Error removing warning overlay", e)
            try { windowManager?.removeView(view) } catch (_: Exception) {}
            warningRoot = null
        }
    }

    //  Cleanup 

    override fun onInterrupt() {
        try {
            Log.d("Lucid", "Service interrupted")
            cancelAllAnimators()
            removeLoadingScreen()
            removeWarningOverlay()
            stopUsageTimer()
            releaseAudioFocus()
            if (::dailyLimitManager.isInitialized) {
                dailyLimitManager.cleanup()
            }
        } catch (e: Exception) {
            Log.e("Lucid", "Error in onInterrupt", e)
        }
    }

    override fun onDestroy() {
        try {
            isServiceRunning = false
            healthCheckHandler.removeCallbacks(healthCheckRunnable)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Exception) {}
            try {
                if (isSystemReceiverRegistered && systemEventReceiver != null) {
                    unregisterReceiver(systemEventReceiver)
                    isSystemReceiverRegistered = false
                    systemEventReceiver = null
                }
            } catch (_: Exception) {}
            super.onDestroy()
            cancelAllAnimators()
            removeLoadingScreen()
            removeWarningOverlay()
            stopUsageTimer()
            activeSessionApps.clear()
            continueCountMap.clear()
            releaseAudioFocus()
            if (::dailyLimitManager.isInitialized) {
                dailyLimitManager.cleanup()
            }
            Log.d("Lucid", "Service destroyed")
        } catch (e: Exception) {
            Log.e("Lucid", "Error in onDestroy", e)
        }
    }
}
