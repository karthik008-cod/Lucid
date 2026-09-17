package com.yuvaan.lucid

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.content.Context
import android.content.SharedPreferences
import android.graphics.*
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Calendar
import java.text.SimpleDateFormat
import java.util.Locale

class DailyLimitManager(private val context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private var windowManager: WindowManager? = null
    private var limitRoot: FrameLayout? = null
    private var midnightTimer: CountDownTimer? = null

    // Tracking state
    private var currentSessionApp: String? = null
    private var sessionStartTimeMs: Long = 0

    // Core functionality

    fun getDailyLimitMins(pkg: String): Int {
        return try {
            val raw = prefs.all["flutter.daily_limit_$pkg"]
            when (raw) {
                is Int -> raw
                is Long -> raw.toInt()
                is Double -> raw.toInt()
                is String -> raw.toIntOrNull() ?: -1
                else -> -1
            }
        } catch (e: Exception) {
            -1
        }
    }

    private fun getUsageTotalMs(pkg: String): Long {
        return try {
            val raw = prefs.all["flutter.usage_total_ms_$pkg"]
            when (raw) {
                is Long -> raw
                is Int -> raw.toLong()
                is Double -> raw.toLong()
                is String -> raw.toLongOrNull() ?: 0L
                else -> 0L
            }
        } catch (e: Exception) {
            0L
        }
    }

    fun recordSessionStart(pkg: String) {
        try {
            currentSessionApp = pkg
            sessionStartTimeMs = System.currentTimeMillis()
            checkAndResetDailyUsage(pkg)
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in recordSessionStart", e)
        }
    }

    fun recordSessionEnd(pkg: String) {
        try {
            if (currentSessionApp == pkg && sessionStartTimeMs > 0) {
                val elapsedMs = System.currentTimeMillis() - sessionStartTimeMs
                if (elapsedMs > 0) {
                    addUsageTime(pkg, elapsedMs)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in recordSessionEnd", e)
        } finally {
            currentSessionApp = null
            sessionStartTimeMs = 0
        }
    }

    private fun checkAndResetDailyUsage(pkg: String) {
        try {
            val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val todayStr = dateFormat.format(java.util.Date())
            val rawDate = prefs.all["flutter.usage_date_$pkg"]
            val storedDate = rawDate?.toString() ?: ""
            
            if (storedDate != todayStr) {
                prefs.edit()
                    .putString("flutter.usage_date_$pkg", todayStr)
                    .putLong("flutter.usage_total_ms_$pkg", 0L)
                    .apply()
            }
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in checkAndResetDailyUsage", e)
        }
    }

    private fun addUsageTime(pkg: String, elapsedMs: Long) {
        try {
            checkAndResetDailyUsage(pkg)
            val currentTotal = getUsageTotalMs(pkg)
            prefs.edit().putLong("flutter.usage_total_ms_$pkg", currentTotal + elapsedMs).apply()
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in addUsageTime", e)
        }
    }

    fun hasExceededDailyLimit(pkg: String): Boolean {
        return try {
            val limitMins = getDailyLimitMins(pkg)
            if (limitMins <= 0) return false

            checkAndResetDailyUsage(pkg)
            val usageMs = getUsageTotalMs(pkg)
            
            usageMs >= (limitMins * 60 * 1000L)
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in hasExceededDailyLimit", e)
            false
        }
    }

    // UI Overlay functionality

    fun isShowingLimitScreen(): Boolean = limitRoot != null

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

    fun showDailyLimitScreen(pkg: String, onLeave: () -> Unit) {
        if (limitRoot != null) return
        
        try {
            windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
            val wm = windowManager ?: return
            val dp = context.resources.displayMetrics.density

            val root = FrameLayout(context)

            // Backdrop
            val bg = object : View(context) {
                private val bgP = Paint().apply { color = Color.parseColor("#E60A0A12") }
                private val glowP = Paint(Paint.ANTI_ALIAS_FLAG)
                override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                    super.onSizeChanged(w, h, oldw, oldh)
                    if (w > 0 && h > 0) {
                        glowP.shader = RadialGradient(
                            w / 2f, h / 2f, w * 0.7f,
                            intArrayOf(Color.parseColor("#152C3D"), Color.parseColor("#0A1420"), Color.TRANSPARENT),
                            floatArrayOf(0f, 0.5f, 1f),
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

            // Card container
            val cardMargin = (dp * 24).toInt()
            val card = object : LinearLayout(context) {
                private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#0F172A") }
                private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp * 1.5f
                    color = Color.parseColor("#38BDF8") // Blue tint
                }
                private val r = dp * 32f
                init {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    setPadding((dp * 28).toInt(), (dp * 36).toInt(), (dp * 28).toInt(), (dp * 32).toInt())
                    setWillNotDraw(false)
                }
                override fun onDraw(canvas: Canvas) {
                    val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
                    canvas.drawRoundRect(rect, r, r, cardPaint)
                    canvas.drawRoundRect(rect, r, r, strokePaint)
                }
            }

            // Title
            val title = TextView(context).apply {
                text = "Daily Limit Reached"
                setTextColor(Color.WHITE)
                textSize = 24f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding(0, 0, 0, (dp * 16).toInt())
            }
            card.addView(title)

            // Motivation quote
            val quotes = listOf(
                "You've already spent enough time here today.",
                "Great job sticking to your limit.",
                "Your future self will thank you.",
                "Time to build something instead.",
                "Come back tomorrow with a fresh mind."
            )
            val quote = TextView(context).apply {
                text = quotes.random()
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 15f; gravity = Gravity.CENTER
                setLineSpacing(0f, 1.3f)
                setPadding(0, 0, 0, (dp * 24).toInt())
            }
            card.addView(quote)

            // Countdown timer wrapper
            val countdownWrapper = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, 0, 0, (dp * 32).toInt())
            }
            
            val countdownLabel = TextView(context).apply {
                text = "Resets in"
                setTextColor(Color.parseColor("#64748B"))
                textSize = 13f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding(0, 0, 0, (dp * 8).toInt())
            }
            countdownWrapper.addView(countdownLabel)

            val countdownTime = TextView(context).apply {
                text = "..."
                setTextColor(Color.parseColor("#38BDF8"))
                textSize = 28f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
            }
            countdownWrapper.addView(countdownTime)
            card.addView(countdownWrapper)

            // Action buttons
            val btnContainer = FrameLayout(context)

            // The Leave Button
            val leaveBtn = object : TextView(context) {
                private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#0369A1") } // Blue
                private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = dp * 1.5f; color = Color.parseColor("#7DD3FC")
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
                text = "   Leave & Do Something Better"
                setTextColor(Color.WHITE)
                textSize = 15f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding((dp * 24).toInt(), (dp * 16).toInt(), (dp * 24).toInt(), (dp * 16).toInt())
                addTouchScaleEffect()
                setOnClickListener {
                    try {
                        removeScreen()
                        onLeave()
                    } catch (e: Exception) {
                        android.util.Log.e("DailyLimitManager", "Error on leave click", e)
                    }
                }
            }
            btnContainer.addView(leaveBtn, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT
            ))

            // Reset state options (Hidden until midnight)
            val resetContainer = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                visibility = View.GONE
            }
            
            val continueToAppBtn = object : TextView(context) {
                private val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#0F172A") }
                private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = dp * 1f; color = Color.parseColor("#334155")
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
                text = "Continue to App"
                setTextColor(Color.parseColor("#94A3B8"))
                textSize = 14f; gravity = Gravity.CENTER
                setTypeface(Typeface.DEFAULT_BOLD)
                setPadding((dp * 20).toInt(), (dp * 14).toInt(), (dp * 20).toInt(), (dp * 14).toInt())
                addTouchScaleEffect()
                setOnClickListener {
                    try {
                        removeScreen()
                    } catch (e: Exception) {
                        android.util.Log.e("DailyLimitManager", "Error on continue click", e)
                    }
                }
            }
            resetContainer.addView(continueToAppBtn, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = (dp * 12).toInt() })

            btnContainer.addView(resetContainer, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT
            ))

            card.addView(btnContainer, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
            ))

            val cardLp = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER
            )
            cardLp.setMargins(cardMargin, 0, cardMargin, 0)
            root.addView(card, cardLp)

            val wParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            try {
                wm.addView(root, wParams)
                limitRoot = root
            } catch (e: Exception) {
                android.util.Log.e("DailyLimitManager", "Error adding limit overlay", e)
                return
            }

            root.alpha = 0f
            root.animate().alpha(1f).setDuration(350).start()

            // Start precision timer to midnight
            startMidnightTimer { h, m, s, isFinished ->
                Handler(Looper.getMainLooper()).post {
                    try {
                        if (limitRoot == null) return@post
                        if (isFinished) {
                            title.text = "Your daily limit has reset."
                            quote.text = "You've been granted a fresh start. Use it wisely."
                            countdownWrapper.visibility = View.GONE
                            leaveBtn.text = "Stay Focused & Leave"
                            resetContainer.visibility = View.VISIBLE
                        } else {
                            val formatted = buildString {
                                if (h > 0) append("${h}h ")
                                if (m > 0 || h > 0) append("${m}m ")
                                append("${s}s")
                            }
                            countdownTime.text = formatted
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("DailyLimitManager", "Error updating midnight countdown", e)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error showing limit screen", e)
            limitRoot = null
        }
    }

    private fun startMidnightTimer(onTick: (hours: Long, mins: Long, secs: Long, isFinished: Boolean) -> Unit) {
        try {
            val now = java.util.Calendar.getInstance()
            val midnight = java.util.Calendar.getInstance().apply {
                add(java.util.Calendar.DAY_OF_YEAR, 1)
                set(java.util.Calendar.HOUR_OF_DAY, 0)
                set(java.util.Calendar.MINUTE, 0)
                set(java.util.Calendar.SECOND, 0)
                set(java.util.Calendar.MILLISECOND, 0)
            }
            val millisUntilMidnight = (midnight.timeInMillis - now.timeInMillis).coerceAtLeast(1000L)

            midnightTimer?.cancel()
            midnightTimer = object : CountDownTimer(millisUntilMidnight, 1000) {
                override fun onTick(millisUntilFinished: Long) {
                    try {
                        val sTotal = millisUntilFinished / 1000
                        val h = sTotal / 3600
                        val m = (sTotal % 3600) / 60
                        val s = sTotal % 60
                        onTick(h, m, s, false)
                    } catch (e: Exception) {
                        android.util.Log.e("DailyLimitManager", "Error in onTick", e)
                    }
                }
                override fun onFinish() {
                    try {
                        onTick(0, 0, 0, true)
                    } catch (e: Exception) {
                        android.util.Log.e("DailyLimitManager", "Error in onFinish", e)
                    }
                }
            }.start()
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error starting midnight timer", e)
        }
    }

    fun removeScreen() {
        try {
            midnightTimer?.cancel()
            midnightTimer = null

            val view = limitRoot ?: return
            view.animate().alpha(0f).setDuration(250)
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        try { windowManager?.removeView(view) } catch (_: Exception) {}
                        if (limitRoot == view) {
                            limitRoot = null
                        }
                    }
                }).start()
        } catch (e: Exception) {
            android.util.Log.e("DailyLimitManager", "Error in removeScreen", e)
            try { windowManager?.removeView(limitRoot) } catch (_: Exception) {}
            limitRoot = null
        }
    }

    fun cleanup() {
        try {
            removeScreen()
        } catch (_: Exception) {}
        currentSessionApp = null
    }
}
