package com.focusflow.productivity.app

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.Calendar

/**
 * FocusFlow MainActivity — Flutter ↔ Android bridge.
 *
 * Houses three MethodChannels:
 *   • com.focusflow.app/usageStats   — usage data + installed-apps enumeration
 *   • com.focusflow.app/permissions  — runtime permission settings deep-links + probes
 *   • com.focusflow.app/blocking     — strict-mode state + blocking-rule push
 *
 * Stability hardening applied (2025):
 *   1. setUninstallBlocked wrapped via safeSetUninstallBlocked() — only Profile/Device
 *      Owner can call this API; as a Device Admin we must fail-soft, not crash.
 *   2. Every external startActivity() call routed through tryStartActivity() — guards
 *      against ActivityNotFoundException on stripped/forked devices.
 *   3. onResume() & configureFlutterEngine() never call setUninstallBlocked unguarded.
 *   4. Cold-launch race (blocked-app intent → Dart listener not yet attached) is
 *      resolved by caching the package name and exposing getInitialBlockedApp so
 *      Dart can pull it on app start, in addition to the warm-launch push channel.
 *   5. Battery-optimization probes/clicks guarded by Build.VERSION_CODES.M.
 *   6. Notification permission request buffered to onRequestPermissionsResult —
 *      Dart's Future only resolves once the user actually answers the OS prompt.
 */
class MainActivity: FlutterActivity() {

    private val USAGE_STATS_CHANNEL = "com.focusflow.app/usageStats"
    private val PERMISSION_CHANNEL = "com.focusflow.app/permissions"
    private val BLOCKING_CHANNEL = "com.focusflow.app/blocking"
    private val TAG = "FocusFlow"

    /**
     * Phase 4: Static channel handle so FocusAccessibilityService can
     * invokeMethod on the Dart side. configureFlutterEngine() assigns it,
     * onDestroy() nulls it. The setter is nullable because Compose/Flutter
     * can recreate engines without recreating the surrounding service.
     * Moved into `companion object` so FocusAccessibilityService (which
     * runs in a separate Service without an Activity reference) can read
     * it as `MainActivity.blockingChannel`.
     */
    companion object {
        @Volatile
        var blockingChannel: MethodChannel? = null
    }

    /** Fix 4: Captures the package that triggered a cold-launch via the "blockedApp" intent extra. */
    private var initialBlockedPackage: String? = null

    /** Phase 1: Optional per-screen block details — present when FocusAccessibilityService
     *  blocked a specific in-app screen (e.g. Instagram Reels) instead of the whole app. */
    private var initialBlockedScreen: String? = null
    private var initialBlockedScreenFriendly: String? = null

    /** Fix 6: Holds the pending notification-permission result until the OS resolves it. */
    private var pendingNotificationResult: MethodChannel.Result? = null
    private val notificationRequestCode = 101

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val blockingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKING_CHANNEL)

        // Phase 4: expose the channel reference so FocusAccessibilityService
        // (which runs in its own Service without a FlutterEngine) can
        // publish per-screen usage updates back to Dart.
        MainActivity.blockingChannel = blockingChannel

        // Process any pending blocked-app intent (cold-launch case)
        handleIntent(intent, blockingChannel)

        // Re-enforce uninstall block on app start if Strict Mode is already on
        tryReapplyUninstallBlock()

        // Reset daily stats if it's a new day
        resetStatsIfNewDay()

        // ─── Usage Stats Channel ───────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_STATS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTodayUsage" -> try {
                    result.success(UsageStatsHelper(this).getTodayUsageStats())
                } catch (e: Exception) {
                    result.error("USAGE_QUERY_FAILED", e.message, null)
                }
                "getInstalledApps" -> {
                    Thread {
                        val apps = getInstalledApps()
                        runOnUiThread {
                            try {
                                result.success(apps)
                            } catch (e: Exception) {
                                result.error("RESULT_DEAD", "Activity gone", null)
                            }
                        }
                    }.start()
                }
                "getAppIcon" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val icon = packageManager.getApplicationIcon(packageName)
                            result.success(drawableToOptimizedBase64(icon))
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", "Could not fetch icon", e.message)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Package name required", null)
                    }
                }
                "getBlockedAttempts" -> {
                    resetStatsIfNewDay()
                    val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
                    result.success(statsPrefs.getInt("total_blocked_attempts", 0))
                }
                "getPhonePickups" -> {
                    resetStatsIfNewDay()
                    val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
                    result.success(statsPrefs.getInt("total_phone_pickups", 0))
                }
                else -> result.notImplemented()
            }
        }

        // ─── Permissions Channel — Fix 2: every startActivity is routed through tryStartActivity ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageStatsPermission" -> result.success(hasUsageStatsPermission())
                "openUsageStatsSettings" -> tryStartActivity(
                    Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result
                )
                "hasAccessibilityPermission" -> result.success(hasAccessibilityPermission())
                "openAccessibilitySettings" -> tryStartActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result
                )
                "hasOverlayPermission" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> tryStartActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    ), result
                )
                "openAppSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    intent.data = Uri.parse("package:$packageName")
                    tryStartActivity(intent, result)
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
                    intent.putExtra(
                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        "FocusFlow requires Device Admin to prevent uninstallation during Strict Mode."
                    )
                    tryStartActivity(intent, result)
                }
                "setUninstallBlocked" -> {
                    // Already wrapped in try/catch below for caller convenience — keep guard here too.
                    val blocked = call.argument<Boolean>("blocked") ?: false
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
                    if (dpm.isAdminActive(adminComponent)) {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                dpm.setUninstallBlocked(adminComponent, packageName, blocked)
                                result.success(true)
                            } else {
                                result.error("UNSUPPORTED", "Android version too low", null)
                            }
                        } catch (e: SecurityException) {
                            Log.w(
                                TAG,
                                "setUninstallBlocked rejected (not Device/Profile Owner): ${e.message}"
                            )
                            result.success(false)  // Fail-soft: caller treats it as "couldn't block"
                        } catch (e: Exception) {
                            result.error("DPM_ERROR", e.message, null)
                        }
                    } else {
                        result.error("ADMIN_NOT_ACTIVE", "Device Admin is not active", null)
                    }
                }
                "isIgnoringBatteryOptimizations" -> {
                    // Fix 5: API added in API 23 — earlier devices are trivially "yes" since
                    // battery-optimization didn't exist back then.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                        result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    // Fix 5: API 23+ only
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        intent.data = Uri.parse("package:$packageName")
                        tryStartActivity(intent, result)
                    } else {
                        result.success(null)
                    }
                }
                "setSafeMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "hasNotificationPermission" -> result.success(hasNotificationPermission())
                "requestNotificationPermission" -> {
                    // Fix 6: only resolve result.success() from onRequestPermissionsResult.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (pendingNotificationResult != null) {
                            result.error("ALREADY_PENDING", "Another notification request is in flight", null)
                            return@setMethodCallHandler
                        }
                        pendingNotificationResult = result
                        try {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                notificationRequestCode
                            )
                        } catch (e: Exception) {
                            Log.w(TAG, "requestPermissions failed: ${e.message}")
                            pendingNotificationResult = null
                            result.success(false)
                        }
                    } else {
                        // Pre-Tiramisu: notification permission is granted by manifest; treat as true
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── Blocking Channel — Fix 4 adds getInitialBlockedApp so Dart can recover from cold-launch race ──
        blockingChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialBlockedApp" -> {
                    val pkg = initialBlockedPackage
                    initialBlockedPackage = null  // Consume so we don't re-trigger on rebuilds
                    result.success(pkg)
                }
                "getInitialBlockedScreen" -> {
                    val screen = initialBlockedScreen
                    initialBlockedScreen = null
                    result.success(screen)
                }
                "getInitialBlockedScreenFriendly" -> {
                    val friendly = initialBlockedScreenFriendly
                    initialBlockedScreenFriendly = null
                    result.success(friendly)
                }
                "getStrictModeStatus" -> {
                    val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
                    result.success(prefs.getBoolean("strictMode", false))
                }
                "updateBlockingRules" -> {
                    val policies = call.argument<List<Map<String, Any>>>("policies")
                    updateRulesInPrefs(policies)
                    result.success(null)
                }
                "updateScreenBlockingRules" -> {
                    val rules = call.argument<List<Map<String, Any>>>("rules")
                    updateScreenRulesInPrefs(rules)
                    result.success(null)
                }
                "getScreenUsageTotals" -> {
                    // Phase 4: hydrate Dart's in-memory state from the
                    // FocusFlowScreenStats SharedPreferences on cold launch
                    // (live updates flow over `onScreenUsageUpdate` while
                    // the app is foregrounded).
                    result.success(readScreenUsageTotals())
                }
                "updateStrictMode" -> handleUpdateStrictMode(call, result, blockingChannel)
                else -> result.notImplemented()
            }
        }
    }

    // ─── Fix 1: extracted updateStrictMode so it's easier to read and gets try/catch on every DPM call ──
    private fun handleUpdateStrictMode(
        call: MethodCall,
        result: MethodChannel.Result,
        blockingChannel: MethodChannel
    ) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val pin = call.argument<String>("pin")
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
        val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)

        if (enabled) {
            val hashedPin = if (pin != null) hashPin(pin) else null
            prefs.edit()
                .putBoolean("strictMode", true)
                .putString("strictModePin", hashedPin)
                .putLong("strictModeStartTime", System.currentTimeMillis())
                .apply()
            safeSetUninstallBlocked(dpm, adminComponent, true)
            result.success(true)
        } else {
            val storedHashedPin = prefs.getString("strictModePin", null)
            val incomingHashedPin = if (pin != null) hashPin(pin) else null
            if (incomingHashedPin != storedHashedPin) {
                result.error("INVALID_PIN", "Incorrect PIN", null)
                return
            }
            val startTime = prefs.getLong("strictModeStartTime", 0L)
            val elapsed = System.currentTimeMillis() - startTime
            if (elapsed < 24 * 60 * 60 * 1000) {
                result.error("STRICT_MODE_LOCKED", "Strict mode cannot be disabled for 24 hours.", null)
                return
            }
            prefs.edit()
                .putBoolean("strictMode", false)
                .putString("strictModePin", null)
                .putLong("strictModeStartTime", 0L)
                .apply()
            safeSetUninstallBlocked(dpm, adminComponent, false)
            result.success(true)
        }
    }

    // ─── Fix 1: helper that wraps the unsafe DPM call. Safe to call from anywhere. ───
    private fun safeSetUninstallBlocked(
        dpm: DevicePolicyManager,
        admin: ComponentName,
        blocked: Boolean
    ) {
        if (!dpm.isAdminActive(admin)) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        try {
            dpm.setUninstallBlocked(admin, packageName, blocked)
        } catch (e: SecurityException) {
            // Only Profile/Device Owner can call this — we're a vanilla Device Admin
            // so the OS will reject. Log and move on; uninstall protection just won't apply.
            Log.w(TAG, "setUninstallBlocked rejected (need Device/Profile Owner): ${e.message}")
        } catch (e: Exception) {
            Log.w(TAG, "setUninstallBlocked error: ${e.message}")
        }
    }

    private fun tryReapplyUninstallBlock() {
        val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("strictMode", false)) {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
            safeSetUninstallBlocked(dpm, adminComponent, true)
        }
    }

    // ─── Fix 2: All startActivity() calls go through this. Returns ok or ActivityNotFound. ───
    private fun tryStartActivity(intent: Intent, result: MethodChannel.Result) {
        try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "startActivity: no handler for ${intent.action}: ${e.message}")
            result.error("ACTIVITY_NOT_FOUND", "No activity found for intent ${intent.action}", e.message)
        } catch (e: SecurityException) {
            Log.w(TAG, "startActivity: security denied ${intent.action}: ${e.message}")
            result.error("SECURITY_DENIED", "OS denied the intent ${intent.action}", e.message)
        } catch (e: Exception) {
            Log.w(TAG, "startActivity: error ${intent.action}: ${e.message}")
            result.error("UNKNOWN", e.message, null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val flutterEngine = flutterEngine ?: return
        val blockingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLOCKING_CHANNEL)
        handleIntent(intent, blockingChannel)
    }

    /**
     * Fix 4 + Phase 1: blocks-app intent handler — caches the package (and
     * optional per-screen details) for cold-launch Dart pull AND pushes the
     * event for the warm-launch listener. The push may be lost if Dart's
     * listener isn't attached yet on cold launch; the cache ensures the
     * overlay still surfaces via Dart's getInitialBlockedApp() and
     * getInitialBlockedScreen*() helpers.
     */
    private fun handleIntent(intent: Intent, channel: MethodChannel) {
        if (intent.getBooleanExtra("blockedApp", false)) {
            val packageName = intent.getStringExtra("blockedPackage") ?: "Unknown"
        val screenKey = intent.getStringExtra("blockedScreen")  // Phase 1, may be null
        val screenFriendly = intent.getStringExtra("blockedScreenFriendly")  // Phase 1
        // silence unused-warning from IDE; intentional nullable-pass-through

            initialBlockedPackage = packageName
            initialBlockedScreen = screenKey
            initialBlockedScreenFriendly = screenFriendly

            channel.invokeMethod(
                "onAppBlocked",
                mapOf(
                    "packageName" to packageName,
                    "screenKey" to screenKey,
                    "screenFriendly" to screenFriendly,
                )
            )
        }
    }

    // ─── Fix 6: Notification permission callback (only fires on API 23+) ───
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationRequestCode) {
            val pending = pendingNotificationResult ?: return
            pendingNotificationResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pending.success(granted)
        }
    }

    private fun hashPin(pin: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(pin.toByteArray())
        return hash.joinToString("") { "%02x".format(it) }
    }

    /**
     * Resets daily stats (blocked attempts + phone pickups) if the stored date
     * is before today. Called at app start and before each stat read.
     */
    private fun resetStatsIfNewDay() {
        val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
        val cal = Calendar.getInstance()
        val todayYear  = cal.get(Calendar.YEAR)
        val todayMonth = cal.get(Calendar.MONTH)
        val todayDay   = cal.get(Calendar.DAY_OF_MONTH)

        val savedYear  = statsPrefs.getInt("stats_year",  -1)
        val savedMonth = statsPrefs.getInt("stats_month", -1)
        val savedDay   = statsPrefs.getInt("stats_day",   -1)

        if (savedYear != todayYear || savedMonth != todayMonth || savedDay != todayDay) {
            statsPrefs.edit()
                .putInt("total_blocked_attempts", 0)
                .putInt("total_phone_pickups", 0)
                .putLong("last_pickup_timestamp", 0L)
                .putInt("stats_year",  todayYear)
                .putInt("stats_month", todayMonth)
                .putInt("stats_day",   todayDay)
                .apply()
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

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
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
        val myPackage = packageName

        for (app in apps) {
            val launchIntent = pm.getLaunchIntentForPackage(app.packageName)
            if (launchIntent != null && app.packageName != myPackage) {
                val map = mutableMapOf<String, Any>()
                map["packageName"] = app.packageName
                map["appName"] = app.loadLabel(pm).toString()
                try {
                    val icon = app.loadIcon(pm)
                    map["icon"] = drawableToOptimizedBase64(icon)
                } catch (_: Exception) {
                    // skip icon if it fails
                }
                result.add(map)
            }
        }
        result.sortBy { (it["appName"] as String).lowercase() }
        return result
    }

    private fun drawableToOptimizedBase64(drawable: Drawable): String {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        val outputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 80, outputStream)
        return Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
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

    /**
     * Phase 4: return every persisted per-screen usage total for the
     * current day, as a list of [packageName, screenKey, usedMs] maps.
     * Mirrors the day stamp that FocusAccessibilityService writes
     * (`ss_year` / `ss_month` / `ss_day`) so we discard yesterday's
     * entries if the user cold-launches while the service hasn't yet
     * ticked over its day-rotation guard.
     */
    private fun readScreenUsageTotals(): List<Map<String, Any>> {
        val prefs = getSharedPreferences("FocusFlowScreenStats", Context.MODE_PRIVATE)
        val cal = Calendar.getInstance()
        val y = cal.get(Calendar.YEAR)
        val m = cal.get(Calendar.MONTH)
        val d = cal.get(Calendar.DAY_OF_MONTH)
        val savedY = prefs.getInt("ss_year", -1)
        val savedM = prefs.getInt("ss_month", -1)
        val savedD = prefs.getInt("ss_day", -1)
        val dayIsCurrent = (savedY == y && savedM == m && savedD == d)
        // If the prefs have NO day stamp yet, the service hasn't run today
        // — trust whatever rows exist (best-effort); once the service ticks,
        // the stamp gets written and stale-but-matching-day rows become
        // safe. If the saved day is older than today, the data IS stale.
        return if (savedY != -1 && !dayIsCurrent) {
            emptyList()
        } else prefs.all.mapNotNull { (k, v) ->
            if (!k.startsWith("usage:")) return@mapNotNull null
            val total = v as? Long ?: return@mapNotNull null
            val parts = k.removePrefix("usage:").split(":", limit = 2)
            if (parts.size != 2) return@mapNotNull null
            mapOf(
                "packageName" to parts[0],
                "screenKey" to parts[1],
                "usedMs" to total,
            )
        }
    }

    /**
     * Phase 3: persist per-screen rules. Encoded as a single Long per key:
     *   bit 0   = isActive (1 if active, 0 if not)
     *   bits 1+ = timeLimitMinutes (zero = "full block")
     * The combined map is keyed as `<packageName>:<screenKey>`.
     * This encoding keeps FocusAccessibilityService reads a single getLong()
     * with no string branching required.
     */
    private fun updateScreenRulesInPrefs(rules: List<Map<String, Any>>?) {
        val prefs = getSharedPreferences("FocusFlowScreenRules", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.clear()
        rules?.forEach { rule ->
            val pkg = rule["packageName"] as? String ?: return@forEach
            val screen = rule["screenKey"] as? String ?: return@forEach
            val timeLimitMinutes = (rule["timeLimitMinutes"] as? Number)?.toInt() ?: 0
            val isActive = rule["isActive"] as? Boolean ?: false
            // Pack: bit 0 = active flag. Rest = minutes shifted up by 1.
            val packed = ((timeLimitMinutes.toLong() shl 1) or (if (isActive) 1L else 0L))
            editor.putLong("$pkg:$screen", packed)
        }
        editor.apply()
    }

    override fun onResume() {
        super.onResume()
        tryReapplyUninstallBlock()
    }

    override fun onDestroy() {
        // Defensively null the channel held by FocusAccessibilityService so
        // a still-living service can't invokeMethod into a dead binary
        // messenger. The service's guard `?:` already silently no-ops in
        // this case, but clearing prevents the broader scene from holding
        // a stale channel reference across engine recreations. Reads
        // `MainActivity.blockingChannel` via the companion object.
        MainActivity.blockingChannel = null
        super.onDestroy()
    }
}
