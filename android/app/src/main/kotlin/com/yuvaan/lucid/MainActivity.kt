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
					val mins = when (val arg = call.arguments) {
						is Number -> arg.toInt()
						is String -> arg.toIntOrNull() ?: 15
						else -> 15
					}
					val prefs = getSharedPreferences("LucidPrefs", Context.MODE_PRIVATE)
					prefs.edit().putInt("warning_interval_mins", mins).apply()
					android.util.Log.d("Lucid", "MainActivity: setWarningInterval to $mins mins")
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
				"isServiceAlive" -> {
					val expectedComponentName = ComponentName(context, LucidAccessibilityService::class.java)
					val enabledServicesSetting = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
					val isEnabled = enabledServicesSetting.contains(expectedComponentName.flattenToString()) || enabledServicesSetting.contains(expectedComponentName.flattenToShortString())
					if (!isEnabled) {
						result.success(false)
					} else {
						val isAlive = LucidAccessibilityService.isServiceRunning ||
							(LucidAccessibilityService.lastHeartbeatMs > 0 && (System.currentTimeMillis() - LucidAccessibilityService.lastHeartbeatMs < 120000))
						result.success(isAlive)
					}
				}
				"isBatteryOptimizationIgnored" -> {
					if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
						val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
						result.success(pm.isIgnoringBatteryOptimizations(packageName))
					} else {
						result.success(true)
					}
				}
				"requestIgnoreBatteryOptimization" -> {
					if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
						try {
							val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
								data = Uri.parse("package:$packageName")
							}
							startActivity(intent)
							result.success(true)
						} catch (e: Exception) {
							val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
							startActivity(intent)
							result.success(true)
						}
					} else {
						result.success(true)
					}
				}
				"openAutostartSettings" -> {
					var opened = false
					val autostartIntents = listOf(
						// Xiaomi / MIUI / HyperOS
						Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
						// Oppo / Realme / ColorOS
						Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
						Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")),
						// Vivo / FuntouchOS / OriginOS
						Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")),
						Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
						// Huawei / Honor
						Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
						// OnePlus
						Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")),
						// Samsung Device Care / Battery
						Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"))
					)
					for (targetIntent in autostartIntents) {
						try {
							startActivity(targetIntent)
							opened = true
							break
						} catch (_: Exception) {}
					}

					if (!opened) {
						try {
							val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
								data = Uri.parse("package:$packageName")
							}
							startActivity(intent)
							opened = true
						} catch (_: Exception) {}
					}
					result.success(opened)
				}
				"openBatterySaverSettings" -> {
					var opened = false
					try {
						val intent = Intent().apply {
							component = ComponentName("com.miui.powerkeeper", "com.miui.powerkeeper.ui.HiddenAppsConfigActivity")
							putExtra("package_name", packageName)
							putExtra("package_label", "Lucid")
						}
						startActivity(intent)
						opened = true
					} catch (_: Exception) {}

					if (!opened && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
						try {
							val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
							startActivity(intent)
							opened = true
						} catch (_: Exception) {}
					}
					result.success(opened)
				}
				"isUsageAccessEnabled" -> {
					val appOps = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
					val mode = appOps.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
					result.success(mode == android.app.AppOpsManager.MODE_ALLOWED)
				}
				"isNotificationPermissionGranted" -> {
					if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
						val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
						result.success(granted)
					} else {
						result.success(true)
					}
				}
				"requestNotificationPermission" -> {
					if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
						requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
						result.success(true)
					} else {
						result.success(true)
					}
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