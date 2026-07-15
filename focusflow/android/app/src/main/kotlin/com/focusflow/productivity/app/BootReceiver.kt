package com.focusflow.productivity.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * FocusFlow BootReceiver — restores the foreground service after the device
 * reboots so Strict Mode / background sync keep running without requiring the
 * user to reopen the app.
 *
 * The receiver reads whether the service was enabled from FocusFlowPrefs and
 * safely starts the declared foreground service. Any failure is logged and
 * swallowed so a boot-time crash cannot take down the system broadcast.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val prefs = context.getSharedPreferences("FocusFlowPrefs", Context.MODE_PRIVATE)
        val serviceEnabled = prefs.getBoolean("foregroundServiceEnabled", false)
        if (!serviceEnabled) return

        try {
            val serviceIntent = Intent().apply {
                setClassName(
                    context,
                    "com.pravera.flutter_foreground_task.service.ForegroundService"
                )
            }
            ContextCompat.startForegroundService(context, serviceIntent)
        } catch (e: Exception) {
            Log.w("FocusFlow", "BootReceiver failed to start foreground service: ${e.message}")
        }
    }
}
