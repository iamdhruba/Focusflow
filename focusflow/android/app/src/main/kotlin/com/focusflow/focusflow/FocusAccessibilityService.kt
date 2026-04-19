package com.focusflow.focusflow

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.util.Log

class FocusAccessibilityService : AccessibilityService() {

    private var strictMode = false
    private lateinit var usageStatsHelper: UsageStatsHelper

    override fun onServiceConnected() {
        super.onServiceConnected()
        usageStatsHelper = UsageStatsHelper(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return
            
            // Load strict mode state
            val prefs = getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
            strictMode = prefs.getBoolean("strictMode", false)

            // Anti-Cheat: Block Settings and Installer if Strict Mode is active
            if (strictMode) {
                if (packageName == "com.android.settings" || packageName == "com.android.packageinstaller") {
                    blockApp()
                    return
                }
            }

            // Check against blocked policies
            checkAndBlock(packageName)
        }
    }

    private fun checkAndBlock(packageName: String) {
        val prefs = getSharedPreferences("FocusFlowRules", Context.MODE_PRIVATE)
        val limitMs = prefs.getLong(packageName, -1)
        
        if (limitMs != -1L) {
            val usage = usageStatsHelper.getTodayUsageStats()[packageName] ?: 0L
            if (usage >= limitMs) {
                blockApp()
            }
        }
    }

    private fun blockApp() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    override fun onInterrupt() {}
}
