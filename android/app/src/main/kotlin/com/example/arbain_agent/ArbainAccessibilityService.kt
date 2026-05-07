package com.example.arbain_agent
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

class ArbainAccessibilityService : AccessibilityService() {

    private var blockedApps = mutableSetOf<String>()

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info
        loadBlockedApps()
    }

    private fun loadBlockedApps() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.blocked_apps", null)
        val apps = mutableSetOf<String>()
        if (raw != null) {
            val cleaned = raw.removePrefix("[").removeSuffix("]")
            if (cleaned.isNotEmpty()) {
                cleaned.split(",").forEach { apps.add(it.trim().removeSurrounding("")) }
            }
        }
        blockedApps = apps
    }

    private fun checkIsRestricted(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.is_restricted", false)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) return
        if (checkIsRestricted()) {
            val intent = packageManager.getLaunchIntentForPackage(applicationContext.packageName)
            intent?.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            startActivity(intent)
            return
        }
        loadBlockedApps()
        if (blockedApps.contains(packageName)) {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(homeIntent)
        }
    }

    override fun onInterrupt() {}
}

