package com.focusflow.productivity.app

import android.accessibilityservice.AccessibilityService
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * FocusFlow AccessibilityService — runtime engine for app + per-screen blocking.
 *
 * Existing responsibilities (Phase 0): app-level time-limit enforcement using
 * `queryAndAggregateUsageStats(UsageStatsManager)`-derived per-day counters.
 *
 * Phase 1 additions:
 *   • Listens for both `TYPE_WINDOW_STATE_CHANGED` and `TYPE_WINDOW_CONTENT_CHANGED`
 *     (the latter fires on tab swaps inside single-activity apps).
 *   • After every content-change event, debounces an off-thread UI walk to
 *     ScreenMatcher.match() inside the existing `ioExecutor`.
 *   • On a match, requires a ~1 s dwell before blocking to avoid triggering on
 *     transient previews during scroll.
 *   • On match + dwell exceeded + replay-guard cooldown passed, launches the
 *     blocker overlay activity with `blockedScreen` and `blockedScreenFriendly`
 *     extras so the UI can render per-screen copy.
 *
 * Stability: all slow work runs on `ioExecutor`; `mainHandler` only dispatches
 * the final Activity-launch / SharedPreferences-touch to the main thread.
 */
class FocusAccessibilityService : AccessibilityService() {

    private lateinit var usageStatsHelper: UsageStatsHelper
    private lateinit var screenStatsPrefs: android.content.SharedPreferences
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private lateinit var mainHandler: Handler

    // ── Phase 1 debounce state ── per package, not global
    private val lastWalkAt = mutableMapOf<String, Long>()
    private val debounceMs = 500L

    // Dwell tracking — `<pkg>:<screenKey>` -> first-detection timestamp
    private val dwellFirstDetectedAt = mutableMapOf<String, Long>()
    private val dwellThresholdMs = 1_000L

    // Replay guard — avoid spamming the blocker every page refresh
    private val lastBlockAt = mutableMapOf<String, Long>()
    private val replayGuardMs = 5 * 60 * 1000L

    // ── Phase 4: per-screen usage attribution ── single-pointer + keyed map ──
    // `dwelledScreenKey` shadows the one screen currently being tracked; maps
    // hold per-day totals. Day rollover resets the in-memory map and the
    // shared prefs date stamp — old `usage_<pkg>:<screen>` rows become stale
    // and get dropped on the next read.
    private var dwelledScreenKey: String? = null
    private var dwelledAt: Long = 0L
    private val screenTickAt = mutableMapOf<String, Long>()
    // `firstPostDwellAt` records the wall clock when a screen first passed
    // the dwellThreshold warmup gate. Used as the delta baseline so the
    // first accumulating tick does NOT credit the warmup window itself
    // (avoids charging the user for the 1s the matcher was warming up).
    private val firstPostDwellAt = mutableMapOf<String, Long>()
    private val screenUsageByKey = mutableMapOf<String, Long>()
    private var lastUsageFlushAt: Long = 0L
    private val usageFlushIntervalMs = 5_000L
    private var screenStatsYear = -1
    private var screenStatsMonth = -1
    private var screenStatsDay = -1

    private val TAG = "FocusFlow"

    /**
     * Strict-mode package set: when Strict Mode is on we block system Settings,
     * the package installer, and Play Store to prevent the user from
     * uninstalling/disabling FocusFlow.
     */
    private val BLOCKED_WHEN_STRICT = listOf(
        "com.android.settings",
        "com.google.android.settings",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.vending"
    )

    override fun onServiceConnected() {
        super.onServiceConnected()
        usageStatsHelper = UsageStatsHelper(this)
        mainHandler = Handler(Looper.getMainLooper())
        screenStatsPrefs = getSharedPreferences(
            "FocusFlowScreenStats",
            Context.MODE_PRIVATE
        )
        ensureScreenStatsDay()
        hydrateScreenUsage()
    }

    override fun onDestroy() {
        // Phase 4: flush the in-flight dwell one last time before tearing down.
        try { persistAndPostScreenUsage() } catch (e: Exception) {
            Log.w(TAG, "onDestroy flush failed: ${e.message}")
        }
        ioExecutor.shutdown()
        try {
            ioExecutor.awaitTermination(1, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            // best-effort shutdown
        }
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        // Flush on explicit unbind (settings page toggle-off) so the user
        // doesn't lose up to `usageFlushIntervalMs` of accumulated dwell.
        try { persistAndPostScreenUsage() } catch (e: Exception) {
            Log.w(TAG, "onUnbind flush failed: ${e.message}")
        }
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val eventType = event.eventType
        if (eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
        ) return

        val packageName = event.packageName?.toString() ?: return
        if (packageName == "com.focusflow.productivity.app") return

        val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
        val isStrict = prefs.getBoolean("strictMode", false)

        if (isStrict && BLOCKED_WHEN_STRICT.contains(packageName)) {
            blockApp(packageName)
            return
        }

        // Existing app-level limit (still off main, still using ioExecutor)
        ioExecutor.execute {
            try { checkAndBlock(packageName) } catch (e: Exception) {
                Log.w(TAG, "checkAndBlock failed for $packageName: ${e.message}")
            }
        }

        // Phase 1: per-screen walker (also off main, also debounced)
        val now = System.currentTimeMillis()
        val lastWalk = lastWalkAt[packageName] ?: 0L
        if (now - lastWalk >= debounceMs) {
            lastWalkAt[packageName] = now
            val source = event.source
            ioExecutor.execute {
                try { walkScreen(packageName, source) } catch (e: Exception) {
                    Log.w(TAG, "walkScreen failed for $packageName: ${e.message}")
                }
            }
        }
    }

    /**
     * Walks the active window's view tree off the main thread and asks
     * ScreenMatcher whether any known screen matches. If a match is sustained
     * for >1 second AND we haven't blocked it in the last 5 minutes, we fire
     * the blocker overlay with the screen-specific intent extras.
     */
    private fun walkScreen(packageName: String, source: AccessibilityNodeInfo?) {
        // Recycle the source — we don't keep references across threads.
        // We use rootInActiveWindow as our walk root; source may be a child.
        val root: AccessibilityNodeInfo = try {
            source ?: rootInActiveWindow ?: return
        } catch (_: Exception) {
            return
        }

        val rule = ScreenMatcher.match(root, packageName)
        // source was a transient ref from the event — recycle it ASAP.
        if (source != null && source !== root) {
            try { source.recycle() } catch (_: Exception) { /* ignore */ }
        }

        val now = System.currentTimeMillis()

        // ── Phase 4: per-screen usage attribution ──
        // Track any matched screen regardless of whether a rule exists yet,
        // so the UI can later prompt "Reels ate 3h today → block it?".
        ensureScreenStatsDay()
        if (rule != null) {
            val usageKey = "${packageName}:${rule.screenKey}"
            tickScreenUsage(usageKey, now)
        } else if (dwelledScreenKey != null && dwelledScreenKey!!.startsWith("$packageName:")) {
            // Walker's currently-dwelling screen just dropped off the
            // matcher recognition. Flush whatever dwell it accumulated so
            // the totals accurately reflect time-spent-on-screen.
            flushAndClearDwelled()
        }

        val key = if (rule != null) "${packageName}:${rule.screenKey}" else null
        if (key == null) {
            // Clear dwell for any matching screens on this pkg
            val toClear = dwellFirstDetectedAt.keys.filter { it.startsWith("$packageName:") }
            toClear.forEach { dwellFirstDetectedAt.remove(it) }
            try { root.recycle() } catch (_: Exception) { /* ignore */ }
            return
        }

        // Phase 3: consult FocusFlowScreenRules prefs — encoded as Long with
        // bit 0 = isActive flag, bits 1+ = timeLimitMinutes. A missing key
        // means the user has not opted into blocking this screen yet.
        val screenRules = getSharedPreferences("FocusFlowScreenRules", Context.MODE_PRIVATE)
        if (!screenRules.contains(key)) {
            try { root.recycle() } catch (_: Exception) { /* ignore */ }
            return
        }
        val packed = screenRules.getLong(key, 0L)
        val isActiveScreen = (packed and 1L) == 1L
        if (!isActiveScreen) {
            try { root.recycle() } catch (_: Exception) { /* ignore */ }
            return
        }

        // The outer `now` (declared earlier in walkScreen) is still in scope
        // and current enough for the debounce/dwell comparison. Re-using it
        // avoids a duplicate-declaration compile error.
        val firstDetectedAt = dwellFirstDetectedAt.getOrPut(key) { now }
        if (now - firstDetectedAt < dwellThresholdMs) {
            try { root.recycle() } catch (_: Exception) { /* ignore */ }
            return
        }

        val lastBlock = lastBlockAt[key] ?: 0L
        if (now - lastBlock < replayGuardMs) {
            try { root.recycle() } catch (_: Exception) { /* ignore */ }
            return
        }

        lastBlockAt[key] = now
        Log.i(TAG, "Blocking screen ${rule!!.friendlyName} on $packageName")
        try { root.recycle() } catch (_: Exception) { /* ignore */ }

        // Posting to main: Activities/Intents require main thread.
        mainHandler.post { blockScreen(packageName, rule.screenKey, rule.friendlyName) }
    }

    /**
     * Bounces the user back to home + starts the blocker activity with
     * extras so the Flutter side can render per-screen copy.
     */
    private fun blockScreen(packageName: String, screenKey: String, friendlyName: String) {
        // Flush any dwell accumulated for the screen we're about to boot them
        // out of, so the post-block total reflects the full session.
        try { flushAndClearDwelled() } catch (_: Exception) {}

        // Increment total attempts counter (existing pattern)
        val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
        resetStatsIfNewDay(statsPrefs)
        val currentTotal = statsPrefs.getInt("total_blocked_attempts", 0)
        statsPrefs.edit().putInt("total_blocked_attempts", currentTotal + 1).apply()

        enforceUninstallBlock(true)

        val blockIntent = Intent(this, MainActivity::class.java)
        blockIntent.putExtra("blockedApp", true)
        blockIntent.putExtra("blockedPackage", packageName)
        blockIntent.putExtra("blockedScreen", screenKey)
        blockIntent.putExtra("blockedScreenFriendly", friendlyName)
        blockIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        try {
            startActivity(blockIntent)
        } catch (e: Exception) {
            Log.w(TAG, "blockScreen startActivity failed: ${e.message}")
        }

        try {
            val home = Intent(Intent.ACTION_MAIN)
            home.addCategory(Intent.CATEGORY_HOME)
            home.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(home)
        } catch (_: Exception) { /* ignore */ }
    }

    // ─── Existing app-level logic (Phase 0, off-thread via ioExecutor) ───

    private fun checkAndBlock(packageName: String) {
        val rulesPrefs = getSharedPreferences("FocusFlowRules", Context.MODE_PRIVATE)
        val limitMs = rulesPrefs.getLong(packageName, -1L)
        if (limitMs == -1L) return

        val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
        val lastHitTime = statsPrefs.getLong("${packageName}_limit_hit_time", 0L)
        val currentTime = System.currentTimeMillis()
        val daySinceHit = currentTime - lastHitTime

        if (lastHitTime > 0L && daySinceHit < LOCKOUT_MS) {
            mainHandler.post { blockApp(packageName) }
            return
        }

        val usage = usageStatsHelper.getTodayUsageStats()[packageName] ?: 0L
        if (usage < limitMs) return

        if (lastHitTime == 0L || daySinceHit >= LOCKOUT_MS) {
            statsPrefs.edit().putLong("${packageName}_limit_hit_time", currentTime).apply()
        }
        val currentCount = statsPrefs.getInt("${packageName}_access_count", 0)
        statsPrefs.edit().putInt("${packageName}_access_count", currentCount + 1).apply()

        mainHandler.post { blockApp(packageName) }
    }

    private fun enforceUninstallBlock(blocked: Boolean) {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(this, DeviceAdminManager::class.java)
            if (dpm.isAdminActive(adminComponent)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    dpm.setUninstallBlocked(adminComponent, packageName, blocked)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "enforceUninstallBlock: ${e.message}")
        }
    }

    private fun blockApp(packageName: String? = null) {
        val statsPrefs = getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)
        resetStatsIfNewDay(statsPrefs)
        val currentTotal = statsPrefs.getInt("total_blocked_attempts", 0)
        statsPrefs.edit().putInt("total_blocked_attempts", currentTotal + 1).apply()

        try {
            val blockIntent = Intent(this, MainActivity::class.java)
            blockIntent.putExtra("blockedApp", true)
            blockIntent.putExtra("blockedPackage", packageName ?: "This App")
            blockIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(blockIntent)
        } catch (e: Exception) {
            Log.w(TAG, "blockApp startActivity failed: ${e.message}")
        }

        try {
            val home = Intent(Intent.ACTION_MAIN)
            home.addCategory(Intent.CATEGORY_HOME)
            home.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(home)
        } catch (_: Exception) { /* ignore */ }
    }

    /**
     * Daily reset of counters that are stored in this service's prefs.
     * Shared with MainActivity's parallel tracking — same logic.
     */
    private fun resetStatsIfNewDay(prefs: android.content.SharedPreferences) {
        val cal = Calendar.getInstance()
        val todayYear = cal.get(Calendar.YEAR)
        val todayMonth = cal.get(Calendar.MONTH)
        val todayDay = cal.get(Calendar.DAY_OF_MONTH)
        val savedYear = prefs.getInt("stats_year", -1)
        val savedMonth = prefs.getInt("stats_month", -1)
        val savedDay = prefs.getInt("stats_day", -1)
        if (savedYear != todayYear || savedMonth != todayMonth || savedDay != todayDay) {
            prefs.edit()
                .putInt("stats_year", todayYear)
                .putInt("stats_month", todayMonth)
                .putInt("stats_day", todayDay)
                .apply()
        }
    }

    override fun onInterrupt() {}

    // ── Phase 4: per-screen usage attribution helpers ─────────────────────────

    /**
     * Day-rotation guard. Called on every walkScreen so a user who dwells
     * across midnight doesn't get yesterday's Reels total bleeding into today.
     *
     * Correctness: the prefs day-stamp write AND the removal of stale
     * `usage:*` keys must be atomic. If they raced and the service crashed
     * after the stamp but before the cleanup, Dart's cold-launch hydrate
     * would see today's stamp + yesterday's totals and surface stale data.
     * We `edit()` all changes in one transaction and `.apply()` last, then
     * clear the in-memory map. If apply() commits and the JVM dies before
     * the in-memory clear, the next walk sees an inconsistency and apply
     * runs again on the next mutation — idempotent.
     */
    private fun ensureScreenStatsDay() {
        val cal = Calendar.getInstance()
        val y = cal.get(Calendar.YEAR)
        val m = cal.get(Calendar.MONTH)
        val d = cal.get(Calendar.DAY_OF_MONTH)
        if (y == screenStatsYear && m == screenStatsMonth && d == screenStatsDay) return

        val editor = screenStatsPrefs.edit()
        // Drop every yesterday's `usage:<pkg>:<screen>` row atomically
        // with writing the new day-stamp keys. SharedPreferences doesn't
        // support wildcard removal, so we iterate; the per-key writes
        // share the same pending edit batch and land together on apply().
        screenStatsPrefs.all.keys
            .filter { it.startsWith("usage:") }
            .forEach { editor.remove(it) }
        editor.putInt("ss_year", y)
        editor.putInt("ss_month", m)
        editor.putInt("ss_day", d)
        editor.apply()

        screenStatsYear = y
        screenStatsMonth = m
        screenStatsDay = d
        screenUsageByKey.clear()
        screenTickAt.clear()
        firstPostDwellAt.clear()
        dwelledScreenKey = null
        dwelledAt = 0L
        lastUsageFlushAt = 0L
    }

    /**
     * Read persisted per-screen totals for the current day back into memory.
     * Cheap: shared preferences cached + ~few screens per user.
     */
    private fun hydrateScreenUsage() {
        if (screenStatsPrefs == null) return
        val all = screenStatsPrefs.all
        for ((k, v) in all) {
            if (!k.startsWith("usage:")) continue
            val total = v as? Long ?: continue
            screenUsageByKey[k.removePrefix("usage:")] = total
        }
    }

    /**
     * Cumulative dwell-tick for the currently-detected screen. Two timings:
     *   • `dwelledAt`        — wall clock when the screen first became the
     *                          dwelled pointer (used as a 1s warmup gate).
     *   • `firstPostDwellAt` — wall clock the FIRST tick that crossed the
     *                          warmup gate (used as the explicit delta
     *                          baseline post-warmup).
     *   • `screenTickAt`     — wall clock of the last accumulated tick
     *                          (used as the delta start for the NEXT tick).
     */
    private fun tickScreenUsage(key: String, now: Long) {
        if (key != dwelledScreenKey) {
            // New screen: flush the previous and reset the dwell clock.
            flushAndClearDwelled()
            dwelledScreenKey = key
            dwelledAt = now
            // Always re-baseline tick on every fresh entry, even if the key
            // has data from a prior in-session visit — otherwise we'd compute
            // delta against an ancient tick and over-report.
            screenTickAt[key] = now
            firstPostDwellAt.remove(key)
            return
        }
        if (now - dwelledAt < dwellThresholdMs) return  // still warming up
        // On the first post-warmup tick of a fresh entry, re-baseline
        // `screenTickAt` to `now` and skip accumulation this round — the
        // delta would otherwise span the entire dwell-threshold warmup
        // window (set at entry time), biasing the total. Subsequent ticks
        // compute their delta against this new baseline.
        if (firstPostDwellAt.putIfAbsent(key, now) == null) {
            screenTickAt[key] = now
            return
        }
        val lastTick = screenTickAt[key] ?: now
        val delta = (now - lastTick).coerceAtLeast(0L)
        if (delta == 0L) return
        screenTickAt[key] = now
        screenUsageByKey[key] = (screenUsageByKey[key] ?: 0L) + delta
        if (now - lastUsageFlushAt >= usageFlushIntervalMs) {
            persistAndPostScreenUsage()
            lastUsageFlushAt = now
        }
    }

    /**
     * Flush + reset the dwelled pointer. Called on no-match, on key-change,
     * on block fire, and on lifecycle teardown.
     *
     * Critical: do NOT remove `screenUsageByKey[key]`. The in-memory mirror
     * of today's running totals must survive across visits within a single
     * service session, otherwise Reels → Home → Reels would reset the
     * counter to 0 mid-day and the next flush would overwrite the persisted
     * daily total with a small number, erasing earlier dwell. Day rollover
     * owns the only legitimate reset path (ensureScreenStatsDay).
     */
    private fun flushAndClearDwelled() {
        val key = dwelledScreenKey ?: return
        // Charge the in-flight dwell (the gap between the last tick and now)
        // before we reset — otherwise we'd lose up to one debounce window of
        // attribution.
        val now = System.currentTimeMillis()
        val lastTick = screenTickAt[key] ?: now
        val trailing = (now - lastTick).coerceAtLeast(0L)
        if (trailing > 0L) {
            screenUsageByKey[key] = (screenUsageByKey[key] ?: 0L) + trailing
        }
        screenTickAt[key] = now
        persistAndPostScreenUsage()
        dwelledScreenKey = null
        dwelledAt = 0L
        // lastUsageFlushAt reset on next tick.
    }

    /**
     * Save per-screen totals to `FocusFlowScreenStats` and post a snapshot
     * to Dart via MainActivity.blockingChannel. Snapshot-before-post avoids
     * any cross-thread map mutation when the listener is dispatched on
     * the main thread while ioExecutor continues to accumulate.
     */
    private fun persistAndPostScreenUsage() {
        if (!::screenStatsPrefs.isInitialized) return
        if (screenUsageByKey.isEmpty()) return
        val snapshot: Map<String, Long> = HashMap(screenUsageByKey)
        val editor = screenStatsPrefs.edit()
        for ((k, v) in snapshot) {
            editor.putLong("usage:$k", v)
        }
        editor.apply()
        mainHandler.post {
            val channel = MainActivity.blockingChannel ?: return@post
            for ((k, total) in snapshot) {
                val parts = k.split(":", limit = 2)
                if (parts.size != 2) continue
                try {
                    channel.invokeMethod(
                        "onScreenUsageUpdate",
                        mapOf(
                            "packageName" to parts[0],
                            "screenKey" to parts[1],
                            "usedMs" to total,
                        )
                    )
                } catch (e: Exception) {
                    Log.w(TAG, "postScreenUsage failed: ${e.message}")
                }
            }
        }
    }

    companion object {
        private const val LOCKOUT_MS = 24L * 60L * 60L * 1000L
    }
}
