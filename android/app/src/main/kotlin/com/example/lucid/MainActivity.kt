package com.example.lucid

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
	private val CHANNEL = "com.example.scroll_stop/accessibility"
	
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			if (call.method == "openSettings") {
				val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
				startActivity(intent)
				result.success(true)
			} else {
				result.notImplemented()
			}
		}
	}
}