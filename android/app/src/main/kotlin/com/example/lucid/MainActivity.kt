package com.example.lucid

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val CHANNEL = "com.example.scroll_stop/accessibility"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"openSettings" -> {
					startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
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
				else -> result.notImplemented()
			}
		}
	}
}