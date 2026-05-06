package com.example.arbain_agent

import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.app.ActivityManager

class AppBlockerService(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var blockedApps = listOf<String>()
    private var isRunning = false

    private val checkRunnable = object : Runnable {
        override fun run() {
            if (isRunning) {
                checkForegroundApp()
                handler.postDelayed(this, 500)
            }
        }
    }

    fun start(blocked: List<String>) {
        blockedApps = blocked
        isRunning = true
        handler.post(checkRunnable)
    }

    fun stop() {
        isRunning = false
        handler.removeCallbacks(checkRunnable)
    }

    fun updateBlockedApps(blocked: List<String>) {
        blockedApps = blocked
    }

    private fun checkForegroundApp() {
        try {
            val usageStatsManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val time = System.currentTimeMillis()
            val stats = usageStatsManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, time - 1000 * 10, time
            )
            if (stats != null && stats.isNotEmpty()) {
                val foregroundApp = stats.maxByOrNull { it.lastTimeUsed }?.packageName ?: return
                if (blockedApps.contains(foregroundApp)) {
                    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(homeIntent)
                }
            }
        } catch (e: Exception) {
            // ignore
        }
    }
}
