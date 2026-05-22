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
import android.util.Log

class ArbainAccessibilityService : AccessibilityService() {

    private var blockedApps = mutableSetOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    private val PROJECT_ID = "arbain-control"
    private val API_KEY = "AIzaSyC67z7V5FfvMPIMIAta8_Ha9TmYJnph190"

    private val pollRunnable = object : Runnable {
        override fun run() {
            pollFirestore()
            pollSchedules()
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
        val uid = getDeviceUid()
        Log.d("ArbainService", "pollFirestore called, uid=$uid")
        if (uid == null) return
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

    private fun pollSchedules() {
        thread {
            try {
                val url = URL("https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/schedules?key=$API_KEY")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                if (conn.responseCode == 200) {
                    val response = conn.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val docs = json.optJSONArray("documents") ?: return@thread
                    val now = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
                    val currentDay = arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[now.get(java.util.Calendar.DAY_OF_WEEK) - 1]
                    val currentMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 + now.get(java.util.Calendar.MINUTE)
                    var shouldRestrict = false
                    for (i in 0 until docs.length()) {
                        val fields = docs.getJSONObject(i).optJSONObject("fields") ?: continue
                        val isActive = fields.optJSONObject("isActive")?.optBoolean("booleanValue") ?: false
                        if (!isActive) continue
                        val daysArr = fields.optJSONObject("days")?.optJSONObject("arrayValue")?.optJSONArray("values") ?: continue
                        val days = mutableListOf<String>()
                        for (j in 0 until daysArr.length()) { days.add(daysArr.getJSONObject(j).optString("stringValue")) }
                        if (!days.contains(currentDay)) continue
                        val startTime = fields.optJSONObject("startTime")?.optString("stringValue") ?: continue
                        val endTime = fields.optJSONObject("endTime")?.optString("stringValue") ?: continue
                        val startMinutes = startTime.split(":")[0].toInt() * 60 + startTime.split(":")[1].toInt()
                        val endMinutes = endTime.split(":")[0].toInt() * 60 + endTime.split(":")[1].toInt()
                        val inSchedule = if (startMinutes <= endMinutes) currentMinutes >= startMinutes && currentMinutes < endMinutes else currentMinutes >= startMinutes || currentMinutes < endMinutes
                        if (inSchedule) { shouldRestrict = true; break }
                    }
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val currentRestricted = prefs.getBoolean("flutter.is_restricted", false)
                    if (shouldRestrict) {
                        prefs.edit().putBoolean("flutter.is_sleep", true).apply()
                        prefs.edit().putBoolean("flutter.is_restricted", true).apply()
                    } else {
                        prefs.edit().putBoolean("flutter.is_sleep", false).apply()
                        if (!currentRestricted) prefs.edit().putBoolean("flutter.is_restricted", false).apply()
                    }
                }
                conn.disconnect()
            } catch (e: Exception) { }
        }
    }

    override fun onInterrupt() {}
}








