package com.focusflow.focusflow

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val USAGE_STATS_CHANNEL = "com.focusflow.app/usageStats"
    private val PERMISSION_CHANNEL = "com.focusflow.app/permissions"
    private val BLOCKING_CHANNEL = "com.focusflow.app/blocking"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Usage Stats Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_STATS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTodayUsage" -> {
                    val helper = UsageStatsHelper(this)
                    result.success(helper.getTodayUsageStats())
                }
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }
                else -> result.notImplemented()
            }
        }

        // Permissions Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
                "openUsageStatsSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "hasAccessibilityPermission" -> result.success(hasAccessibilityPermission())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                    startActivity(intent)
                    result.success(null)
                }
                "isDeviceAdminActive" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
                    result.success(dpm.isAdminActive(adminComponent))
                }
                "requestDeviceAdmin" -> {
                    val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                    intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "FocusFlow requires Device Admin to prevent uninstallation.")
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Blocking Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateBlockingRules" -> {
                    val policies = call.argument<List<Map<String, Any>>>("policies")
                    updateRulesInPrefs(policies)
                    result.success(null)
                }
                "updateStrictMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("strictMode", enabled).apply()
                    result.success(null)
                }
                "startForegroundService", "stopForegroundService" -> {
                    // Stubs for foreground service control
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasAccessibilityPermission(): Boolean {
        val accessibilityService = ComponentName(this, FocusAccessibilityService::class.java).flattenToString()
        val settingValue = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        return settingValue?.contains(accessibilityService) == true
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val result = mutableListOf<Map<String, Any>>()
        for (app in apps) {
            if (pm.getLaunchIntentForPackage(app.packageName) != null) {
                val map = mutableMapOf<String, Any>()
                map["packageName"] = app.packageName
                map["appName"] = app.loadLabel(pm).toString()
                // Icon is omitted for brevity/performance in this demo
                result.add(map)
            }
        }
        return result
    }

    private fun updateRulesInPrefs(policies: List<Map<String, Any>>?) {
        val prefs = getSharedPreferences("FocusFlowRules", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.clear()
        policies?.forEach { policy ->
            val packageName = policy["packageName"] as String
            val timeLimitMinutes = (policy["timeLimitMinutes"] as Number).toLong()
            val isActive = policy["isActive"] as Boolean
            if (isActive) {
                editor.putLong(packageName, timeLimitMinutes * 60 * 1000)
            }
        }
        editor.apply()
    }
}
