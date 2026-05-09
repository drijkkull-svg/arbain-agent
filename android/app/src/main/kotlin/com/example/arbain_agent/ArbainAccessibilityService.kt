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
    private var sleepOverlayView: android.view.View? = null
    private val PROJECT_ID = "arbain-control"
    private val API_KEY = "AIzaSyC67z7V5FfvMPIMIAta8_Ha9TmYJnph190"

    private val pollRunnable = object : Runnable {
        override fun run() {
            pollFirestore()
            pollSchedules()
            handler.postDelayed(this, 10000)
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
            } catch (e: Exception) { Log.e("ArbainService", "pollSchedules error: ${e.message}", e) }
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
        if (packageName == applicationContext.packageName) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.is_sleep", false)) {
            prefs.edit().putBoolean("flutter.is_restricted", false).apply()
        }
        return
    }
        val isSleep = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.is_sleep", false)
        if (packageName.contains("launcher") || packageName.contains("home")) return
        if (checkIsRestricted() && !isSleep) {
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

        private fun showSleepOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
        val params = android.view.WindowManager.LayoutParams(
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or android.view.WindowManager.LayoutParams.FLAG_FULLSCREEN or android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or android.view.WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS,
            android.graphics.PixelFormat.TRANSLUCENT
        )
        val prefs2 = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val santriName = prefs2.getString("flutter.username", "") ?: ""
        val kamar = prefs2.getString("flutter.kamar", "") ?: ""
        val now2 = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
        val jam = String.format("%02d:%02d", now2.get(java.util.Calendar.HOUR_OF_DAY), now2.get(java.util.Calendar.MINUTE))
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setBackgroundColor(android.graphics.Color.parseColor("#080C18"))
            systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            setPadding(80, 0, 80, 0)
        }
        android.widget.TextView(this).also { v -> v.text = "\uD83C\uDF19"; v.textSize = 52f; v.gravity = android.view.Gravity.CENTER; v.setPadding(0,0,0,12); layout.addView(v) }
        android.widget.TextView(this).also { v -> v.text = jam; v.textSize = 56f; v.setTypeface(null, android.graphics.Typeface.BOLD); v.setTextColor(android.graphics.Color.WHITE); v.gravity = android.view.Gravity.CENTER; v.setPadding(0,0,0,4); layout.addView(v) }
        android.widget.TextView(this).also { v -> v.text = "JAM TIDUR"; v.textSize = 15f; v.setTypeface(null, android.graphics.Typeface.BOLD); v.setTextColor(android.graphics.Color.parseColor("#4ECDC4")); v.gravity = android.view.Gravity.CENTER; v.letterSpacing = 0.3f; v.setPadding(0,0,0,8); layout.addView(v) }
        android.widget.TextView(this).also { v -> v.text = "HP sedang dikunci oleh pengurus"; v.textSize = 12f; v.setTextColor(android.graphics.Color.parseColor("#556677")); v.gravity = android.view.Gravity.CENTER; v.setPadding(0,0,0,44); layout.addView(v) }
        android.widget.TextView(this).also { v -> v.text = "PONPES AL-MUBAROK AL-ARBA'IN"; v.textSize = 12f; v.setTypeface(null, android.graphics.Typeface.BOLD); v.setTextColor(android.graphics.Color.parseColor("#3DBDB5")); v.gravity = android.view.Gravity.CENTER; v.setPadding(0,0,0,32); layout.addView(v) }
        if (santriName.isNotEmpty()) {
            android.widget.TextView(this).also { v -> v.text = "NAMA SANTRI"; v.textSize = 10f; v.setTextColor(android.graphics.Color.parseColor("#334455")); v.gravity = android.view.Gravity.CENTER; v.letterSpacing = 0.2f; layout.addView(v) }
            android.widget.TextView(this).also { v -> v.text = santriName; v.textSize = 22f; v.setTypeface(null, android.graphics.Typeface.BOLD); v.setTextColor(android.graphics.Color.WHITE); v.gravity = android.view.Gravity.CENTER; v.setPadding(0,4,0,28); layout.addView(v) }
        }
        if (kamar.isNotEmpty()) {
            android.widget.TextView(this).also { v -> v.text = "KAMAR"; v.textSize = 10f; v.setTextColor(android.graphics.Color.parseColor("#334455")); v.gravity = android.view.Gravity.CENTER; v.letterSpacing = 0.2f; layout.addView(v) }
            android.widget.TextView(this).also { v -> v.text = kamar; v.textSize = 22f; v.setTypeface(null, android.graphics.Typeface.BOLD); v.setTextColor(android.graphics.Color.WHITE); v.gravity = android.view.Gravity.CENTER; v.setPadding(0,4,0,0); layout.addView(v) }
        }
        android.widget.TextView(this).also { v -> v.text = "Berbasis Teknologi - Arbain Agent"; v.textSize = 10f; v.setTextColor(android.graphics.Color.parseColor("#232F3E")); v.gravity = android.view.Gravity.CENTER; layout.addView(v) }
        handler.post { if (sleepOverlayView == null) { wm.addView(layout, params); sleepOverlayView = layout; layout.systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE } }
    }
    private fun hideSleepOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
        handler.post { sleepOverlayView?.let { try { wm.removeView(it) } catch (e: Exception) {} ; sleepOverlayView = null }; val homeIntent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME); flags = Intent.FLAG_ACTIVITY_NEW_TASK }; startActivity(homeIntent) }
    }

    private fun pollSchedules() {
        thread {
            try {
                Log.d("ArbainService", "pollSchedules called")
                val nowDebug = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
                Log.d("ArbainService", "current day=${arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[nowDebug.get(java.util.Calendar.DAY_OF_WEEK)-1]}, minutes=${nowDebug.get(java.util.Calendar.HOUR_OF_DAY)*60+nowDebug.get(java.util.Calendar.MINUTE)}")
                val url = URL("https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/schedules?key=$API_KEY")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                if (conn.responseCode == 200) {
                    val response = conn.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val docsKey = json.keys().asSequence().firstOrNull()
                        Log.d("ArbainService", "json keys=$docsKey, hasDocuments=${json.has("documents")}")
                        val docs = json.optJSONArray("documents") ?: run { Log.d("ArbainService", "no documents"); hideSleepOverlay(); val prefs2 = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE); prefs2.edit().putBoolean("flutter.is_sleep", false).apply(); prefs2.edit().putBoolean("flutter.is_restricted", false).apply(); return@thread }
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
                        Log.d("ArbainService", "check: days=$days curDay=$currentDay start=$startMinutes end=$endMinutes curMin=$currentMinutes inSchedule=$inSchedule")
                        if (inSchedule) { shouldRestrict = true; break }
                                    }
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val currentRestricted = prefs.getBoolean("flutter.is_restricted", false)
                    if (shouldRestrict) {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val admin = android.content.ComponentName(this, ArbainDeviceAdminReceiver::class.java)
                        if (dpm.isAdminActive(admin)) {
    showSleepOverlay()
            Log.d("ArbainService", "isAdminActive=true, calling lockNow")
    handler.post { 
        try {
            dpm.lockNow()
            Log.d("ArbainService", "lockNow called successfully")
        } catch (ex: Exception) {
            Log.e("ArbainService", "lockNow error: ${ex.message}")
        }
    }
} else {
    Log.d("ArbainService", "isAdminActive=FALSE, cannot lock")
}
                        prefs.edit().putBoolean("flutter.is_sleep", true).apply()
                        prefs.edit().putBoolean("flutter.is_restricted", true).apply()
                    } else {
                        prefs.edit().putBoolean("flutter.is_sleep", false).apply()
                        hideSleepOverlay()
                        if (!currentRestricted) prefs.edit().putBoolean("flutter.is_restricted", false).apply()
                    }
                }
                conn.disconnect()
            } catch (e: Exception) { Log.e("ArbainService", "pollSchedules error: ${e.message}", e) }
        }
    }

    override fun onInterrupt() {}
}










































