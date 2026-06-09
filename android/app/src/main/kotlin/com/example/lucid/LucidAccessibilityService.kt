package com.example.lucid

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.CountDownTimer
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class LucidAccessibilityService : AccessibilityService() {

	private var currentApp = ""
	private var windowManager: WindowManager? = null
	private var overlayView: LinearLayout? = null
	private var warningOverlayView: LinearLayout? = null
	private var countdownTimer: CountDownTimer? = null
	private var usageTimer: CountDownTimer? = null
	private var isLoadingScreenActive = false
	private var isAppSessionActive = false

	// 15 minutes in milliseconds
	private val WARNING_INTERVAL_MS = 15 * 60 * 1000L

	// Target apps to intercept
	private val targetApps = setOf(
		"com.google.android.youtube",
		"com.instagram.android",
		"com.snapchat.android",
		"com.twitter.android",
		"com.facebook.katana",
		"com.zhiliaoapp.musically",    // TikTok
		"com.reddit.frontpage"
	)

	override fun onAccessibilityEvent(event: AccessibilityEvent) {
		if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
			val openedPackage = event.packageName?.toString() ?: return

			if (openedPackage == currentApp) return
			currentApp = openedPackage

			if (targetApps.contains(currentApp)) {
				// User opened a target app
				if (!isLoadingScreenActive) {
					stopUsageTimer()
					showMindfulLoadingScreen()
				}
			} else {
				// User left a target app
				removeLoadingScreen()
				stopUsageTimer()
				isAppSessionActive = false
			}
		}
	}

	// ─── LOADING SCREEN (60-second friction wall) ─────────────────────────────

	private fun showMindfulLoadingScreen() {
		isLoadingScreenActive = true
		windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

		val root = LinearLayout(this).apply {
			orientation = LinearLayout.VERTICAL
			setBackgroundColor(Color.parseColor("#0D0D0D"))
			gravity = Gravity.CENTER
			setPadding(80, 80, 80, 80)
		}

		// Emoji / icon row
		val emojiText = TextView(this).apply {
			text = "🧠"
			textSize = 56f
			gravity = Gravity.CENTER
		}

		// Title
		val titleText = TextView(this).apply {
			text = "Take a Breath"
			setTextColor(Color.parseColor("#E0E0E0"))
			textSize = 30f
			gravity = Gravity.CENTER
			setTypeface(null, Typeface.BOLD)
			setPadding(0, 32, 0, 0)
		}

		// Subtitle
		val subtitleText = TextView(this).apply {
			text = "Your brain deserves 60 seconds to decide if this is worth your time."
			setTextColor(Color.parseColor("#9E9E9E"))
			textSize = 15f
			gravity = Gravity.CENTER
			setPadding(0, 20, 0, 60)
		}

		// Countdown pill
		val countdownText = TextView(this).apply {
			text = "Opening in 60 seconds..."
			setTextColor(Color.parseColor("#BB86FC"))
			textSize = 18f
			gravity = Gravity.CENTER
			setTypeface(null, Typeface.BOLD)
			setPadding(40, 28, 40, 28)
			setBackgroundColor(Color.parseColor("#1E1E2E"))
		}

		// Divider space
		val spacer = TextView(this).apply {
			setPadding(0, 48, 0, 0)
		}

		// Escape button
		val escapeButton = Button(this).apply {
			text = "← Go Back Instead"
			setBackgroundColor(Color.parseColor("#CF6679"))
			setTextColor(Color.WHITE)
			textSize = 15f
			setPadding(40, 24, 40, 24)
			setOnClickListener {
				performGlobalAction(GLOBAL_ACTION_HOME)
				removeLoadingScreen()
			}
		}

		root.addView(emojiText)
		root.addView(titleText)
		root.addView(subtitleText)
		root.addView(countdownText)
		root.addView(spacer)
		root.addView(escapeButton)

		val params = WindowManager.LayoutParams(
			WindowManager.LayoutParams.MATCH_PARENT,
			WindowManager.LayoutParams.MATCH_PARENT,
			WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
			WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
			PixelFormat.TRANSLUCENT
		)

		windowManager?.addView(root, params)
		overlayView = root

		// 60-second countdown
		countdownTimer = object : CountDownTimer(60_000, 1000) {
			override fun onTick(millisUntilFinished: Long) {
				val seconds = millisUntilFinished / 1000
				Handler(Looper.getMainLooper()).post {
					countdownText.text = "Opening in $seconds second${if (seconds == 1L) "" else "s"}..."
				}
			}
			override fun onFinish() {
				removeLoadingScreen()
				// Start 15-min session usage timer AFTER the delay screen closes
				startUsageTimer()
				isAppSessionActive = true
			}
		}.start()
	}

	private fun removeLoadingScreen() {
		countdownTimer?.cancel()
		countdownTimer = null
		if (overlayView != null && windowManager != null) {
			try { windowManager?.removeView(overlayView) } catch (_: Exception) {}
			overlayView = null
		}
		isLoadingScreenActive = false
	}

	// ─── 15-MINUTE USAGE WARNING ──────────────────────────────────────────────

	private fun startUsageTimer() {
		stopUsageTimer()
		// Fire every 15 minutes, indefinitely by restarting
		scheduleNextWarning()
	}

	private fun scheduleNextWarning() {
		usageTimer = object : CountDownTimer(WARNING_INTERVAL_MS, 1000) {
			override fun onTick(millisUntilFinished: Long) {}
			override fun onFinish() {
				// Only show if still in a target app
				if (targetApps.contains(currentApp)) {
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

		val root = LinearLayout(this).apply {
			orientation = LinearLayout.VERTICAL
			setBackgroundColor(Color.parseColor("#CC000000"))
			gravity = Gravity.CENTER
			setPadding(80, 80, 80, 80)
		}

		// Inner card
		val card = LinearLayout(this).apply {
			orientation = LinearLayout.VERTICAL
			setBackgroundColor(Color.parseColor("#1C1C2E"))
			gravity = Gravity.CENTER
			setPadding(60, 60, 60, 60)
		}

		val warningEmoji = TextView(this).apply {
			text = "⏰"
			textSize = 48f
			gravity = Gravity.CENTER
		}

		val warningTitle = TextView(this).apply {
			text = "15 Minutes Gone."
			setTextColor(Color.parseColor("#FF6B6B"))
			textSize = 26f
			gravity = Gravity.CENTER
			setTypeface(null, Typeface.BOLD)
			setPadding(0, 24, 0, 0)
		}

		val warningBody = TextView(this).apply {
			text = "You've used 15 precious minutes of your life here.\n\nIs this really how you want to spend your time?"
			setTextColor(Color.parseColor("#CCCCCC"))
			textSize = 15f
			gravity = Gravity.CENTER
			setPadding(0, 20, 0, 40)
		}

		// Continue button
		val continueButton = Button(this).apply {
			text = "Keep Going (15 min more)"
			setBackgroundColor(Color.parseColor("#2D2D3F"))
			setTextColor(Color.parseColor("#9E9E9E"))
			textSize = 13f
			setPadding(40, 20, 40, 20)
			setOnClickListener {
				removeWarningOverlay()
				// Restart 15-min timer for next warning
				scheduleNextWarning()
			}
		}

		// Go back button
		val spacer = TextView(this).apply { setPadding(0, 16, 0, 0) }
		val goBackButton = Button(this).apply {
			text = "✓ I'll Do Something Better"
			setBackgroundColor(Color.parseColor("#4CAF50"))
			setTextColor(Color.WHITE)
			textSize = 14f
			setTypeface(null, Typeface.BOLD)
			setPadding(40, 24, 40, 24)
			setOnClickListener {
				performGlobalAction(GLOBAL_ACTION_HOME)
				removeWarningOverlay()
				stopUsageTimer()
				isAppSessionActive = false
			}
		}

		card.addView(warningEmoji)
		card.addView(warningTitle)
		card.addView(warningBody)
		card.addView(goBackButton)
		card.addView(spacer)
		card.addView(continueButton)
		root.addView(card)

		val params = WindowManager.LayoutParams(
			WindowManager.LayoutParams.MATCH_PARENT,
			WindowManager.LayoutParams.MATCH_PARENT,
			WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
			WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
			PixelFormat.TRANSLUCENT
		)

		windowManager?.addView(root, params)
		warningOverlayView = root
	}

	private fun removeWarningOverlay() {
		if (warningOverlayView != null && windowManager != null) {
			try { windowManager?.removeView(warningOverlayView) } catch (_: Exception) {}
			warningOverlayView = null
		}
	}

	override fun onInterrupt() {
		removeLoadingScreen()
		removeWarningOverlay()
		stopUsageTimer()
	}

	override fun onDestroy() {
		super.onDestroy()
		removeLoadingScreen()
		removeWarningOverlay()
		stopUsageTimer()
	}
}
