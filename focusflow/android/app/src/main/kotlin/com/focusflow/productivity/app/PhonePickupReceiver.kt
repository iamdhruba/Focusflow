package com.focusflow.productivity.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar

class PhonePickupReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_SCREEN_ON || intent.action == Intent.ACTION_USER_PRESENT) {
            val prefs = context.getSharedPreferences("FocusFlowStats", Context.MODE_PRIVATE)

            // ── Daily Reset ───────────────────────────────────────────────────
            val cal        = Calendar.getInstance()
            val todayYear  = cal.get(Calendar.YEAR)
            val todayMonth = cal.get(Calendar.MONTH)
            val todayDay   = cal.get(Calendar.DAY_OF_MONTH)

            val savedYear  = prefs.getInt("stats_year",  -1)
            val savedMonth = prefs.getInt("stats_month", -1)
            val savedDay   = prefs.getInt("stats_day",   -1)

            val editor = prefs.edit()
            if (savedYear != todayYear || savedMonth != todayMonth || savedDay != todayDay) {
                // New day — reset counters
                editor
                    .putInt("total_blocked_attempts", 0)
                    .putInt("total_phone_pickups", 0)
                    .putLong("last_pickup_timestamp", 0L)
                    .putInt("stats_year",  todayYear)
                    .putInt("stats_month", todayMonth)
                    .putInt("stats_day",   todayDay)
                    .apply()
                // First pickup of the day — count it immediately
                editor.putInt("total_phone_pickups", 1).apply()
                return
            }

            // ── Rate Limiting: only count if last pickup was > 5 s ago ────────
            val pickups  = prefs.getInt("total_phone_pickups", 0)
            val lastTime = prefs.getLong("last_pickup_timestamp", 0L)
            val now      = System.currentTimeMillis()

            if (now - lastTime > 5000) {
                editor
                    .putInt("total_phone_pickups", pickups + 1)
                    .putLong("last_pickup_timestamp", now)
                    .apply()
            }
        }
    }
}
