package com.example.arbain_agent
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject
import kotlin.concurrent.thread

class ArbainAccessibilityService : AccessibilityService() {

    private var blockedApps = mutableSetOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    private val PROJECT_ID = "arbain-control"
    private val API_KEY = "AIzaSyC67z7V5FfvMPIMIAta8_Ha9TmYJnph190"

    private val pollRunnable = object : Runnable {
        override fun run() {
            pollFirestore()
            handler.postDelayed(this, 30000)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info
        loadBlockedApps()
        handler.post(pollRunnable)
    }

    private fun getDeviceUid(): String? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.device_uid", null)
    }

    private fun pollFirestore() {
        val uid = getDeviceUid() ?: return
        thread {
            try {
                val url = URL("https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/devices/$uid?key=$API_KEY")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                if (conn.responseCode == 200) {
                    val response = conn.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val fields = json.optJSONObject("fields") ?: return@thread
                    val isRestricted = fields.optJSONObject("isRestricted")?.optBoolean("booleanValue") ?: false
                    val blockedAppsArr = fields.optJSONObject("blockedApps")?.optJSONObject("arrayValue")?.optJSONArray("values")
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.is_restricted", isRestricted).apply()
                    if (blockedAppsArr != null) {
                        val apps = mutableListOf<String>()
                        for (i in 0 until blockedAppsArr.length()) {
                            apps.add(blockedAppsArr.getJSONObject(i).optString("stringValue"))
                        }
                        val json2 = "[" + apps.joinToString(",") { "\"$it\"" } + "]"
                        prefs.edit().putString("flutter.blocked_apps", json2).apply()
                    }
                }
                conn.disconnect()
            } catch (e: Exception) { }
        }
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

    override fun onServiceDisconnected() {
        handler.removeCallbacks(pollRunnable)
    }

    override fun onInterrupt() {}
}


