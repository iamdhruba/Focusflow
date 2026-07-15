package com.focusflow.productivity.app

import android.app.usage.UsageStatsManager
import android.content.Context
import java.util.*

class UsageStatsHelper(private val context: Context) {

    fun getTodayUsageStats(): Map<String, Long> {
        val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)
        val result = mutableMapOf<String, Long>()
        for ((packageName, usageStats) in stats) {
            result[packageName] = usageStats.totalTimeInForeground
        }
        return result
    }
}
