package com.yuvaan.lucid

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val CHANNEL = "com.yuvaan.lucid/accessibility"
	private val APPS_CHANNEL = "lucid/apps"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"openSettings" -> {
					startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
					result.success(true)
				}
				"openAppInfo" -> {
					val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
						data = Uri.parse("package:$packageName")
					}
					startActivity(intent)
					result.success(true)
				}
				"openUsageAccess" -> {
					try {
						val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
							data = Uri.parse("package:$packageName")
						}
						startActivity(intent)
					} catch (e: Exception) {
						// Some devices don't support the package-specific URI
						startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
					}
					result.success(true)
				}
				"setTargetApps" -> {
					val apps = call.arguments as? List<String> ?: emptyList()
					val prefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
					prefs.edit().putString("target_apps", apps.joinToString(",")).apply()
					result.success(true)
				}
				"setWarningInterval" -> {
					val mins = call.arguments as? Int ?: 15
					val prefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
					prefs.edit().putInt("warning_interval_mins", mins).apply()
					result.success(true)
				}
				"getWarningInterval" -> {
					val prefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
					val mins = prefs.getInt("warning_interval_mins", 15)
					result.success(mins)
				}
				"isAccessibilityEnabled" -> {
					val expectedComponentName = ComponentName(context, LucidAccessibilityService::class.java)
					val enabledServicesSetting = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
					val isEnabled = enabledServicesSetting.contains(expectedComponentName.flattenToString()) || enabledServicesSetting.contains(expectedComponentName.flattenToShortString())
					result.success(isEnabled)
				}
				else -> result.notImplemented()
			}
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL).setMethodCallHandler { call, result ->
			if (call.method == "getLauncherApps") {
				// Run on background thread to avoid blocking the main/UI thread
				Thread {
					try {
						val pm = packageManager
						val intent = Intent(Intent.ACTION_MAIN, null).apply {
							addCategory(Intent.CATEGORY_LAUNCHER)
						}
						val apps = pm.queryIntentActivities(intent, 0)
						val appList = apps.map {
							mapOf(
								"name" to it.loadLabel(pm).toString(),
								"package" to it.activityInfo.packageName
							)
						}.distinctBy {
							it["package"]
						}.sortedBy {
							it["name"]
						}
						android.os.Handler(android.os.Looper.getMainLooper()).post {
							result.success(appList)
						}
					} catch (e: Exception) {
						android.os.Handler(android.os.Looper.getMainLooper()).post {
							result.error("ERROR", e.message, null)
						}
					}
				}.start()
			} else {
				result.notImplemented()
			}
		}
	}
}