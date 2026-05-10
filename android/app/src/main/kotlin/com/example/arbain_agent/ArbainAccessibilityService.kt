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

    @Volatile private var blockedApps = mutableSetOf<String>()
    @Volatile private var blockedAppsNgaji = mutableSetOf<String>()
    private var appTimeLimits = mutableMapOf<String, Int>()
    private var appUsageToday = mutableMapOf<String, Long>()
    private var currentAppStart: Long = 0L
    private var currentAppPackage: String = ""
    private var lastResetDay: Int = -1
    private val handler = Handler(Looper.getMainLooper())
    private var sleepOverlayView: android.view.View? = null
    private val PROJECT_ID = "arbain-control"
    private val API_KEY = "AIzaSyC67z7V5FfvMPIMIAta8_Ha9TmYJnph190"
    private var isPolling = false

    private val BROWSER_PACKAGES = setOf("com.android.chrome", "org.mozilla.firefox", "com.opera.browser", "com.microsoft.emmx")

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!isPolling) {
                isPolling = true
                pollFirestore()
                pollSchedules()
                isPolling = false
            }
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isNgaji = prefs.getBoolean("flutter.is_ngaji", false)
            val isBrowser = BROWSER_PACKAGES.contains(currentAppPackage)
            val browserAllowed = prefs.getBoolean("flutter.browser_allowed", false)
            val isBlocked = when {
                isNgaji && isBrowser -> false
                isNgaji -> blockedAppsNgaji.contains(currentAppPackage)
                isBrowser -> !browserAllowed
                else -> blockedApps.contains(currentAppPackage)
            }
            val shouldBlock = currentAppPackage.isNotEmpty() && (isBlocked || isOverTimeLimit(currentAppPackage))
            if (shouldBlock) {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                Log.d("ArbainService", "Closing app: $currentAppPackage")
            }
            handler.postDelayed(this, 3000)
        }
    }

    override fun onServiceConnected() {
        Log.d("ArbainService", "onServiceConnected called!")
        super.onServiceConnected()
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info
        loadBlockedApps()
        loadAppUsageToday()
        handler.post(pollRunnable)
    }

    private fun getDeviceUid(): String? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.device_uid", null)
    }

    private fun pollFirestore() {
        val uid = getDeviceUid() ?: return
        Log.d("ArbainService", "pollFirestore called, uid=$uid")
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
                    val browserAllowed = fields.optJSONObject("browserAllowed")?.optBoolean("booleanValue") ?: false
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putBoolean("flutter.is_restricted", isRestricted)
                        .putBoolean("flutter.browser_allowed", browserAllowed)
                        .apply()
                    val blockedAppsArr = fields.optJSONObject("blockedApps")?.optJSONObject("arrayValue")?.optJSONArray("values")
                    val newApps = mutableSetOf<String>()
                    if (blockedAppsArr != null) {
                        for (i in 0 until blockedAppsArr.length()) {
                            newApps.add(blockedAppsArr.getJSONObject(i).optString("stringValue"))
                        }
                    }
                    blockedApps = newApps
                    Log.d("ArbainService", "blockedApps updated: $newApps")
                    val timeLimitsObj = fields.optJSONObject("appTimeLimits")?.optJSONObject("mapValue")?.optJSONObject("fields")
                    if (timeLimitsObj != null) {
                        appTimeLimits.clear()
                        fun flattenMap(obj: org.json.JSONObject, prefix: String) {
                            obj.keys().forEach { key ->
                                val fullKey = if (prefix.isEmpty()) key else "$prefix.$key"
                                val fieldObj = obj.optJSONObject(key)
                                val innerMap = fieldObj?.optJSONObject("mapValue")?.optJSONObject("fields")
                                if (innerMap != null) {
                                    flattenMap(innerMap, fullKey)
                                } else {
                                    val minutes = when {
                                        fieldObj?.has("integerValue") == true -> fieldObj.optString("integerValue").toIntOrNull() ?: 0
                                        fieldObj?.has("doubleValue") == true -> fieldObj.optDouble("doubleValue").toInt()
                                        else -> 0
                                    }
                                    if (minutes > 0) appTimeLimits[fullKey] = minutes
                                }
                            }
                        }
                        flattenMap(timeLimitsObj, "")
                        Log.d("ArbainService", "appTimeLimits updated: $appTimeLimits")
                    }
                }
                conn.disconnect()
            } catch (e: Exception) { Log.e("ArbainService", "pollFirestore error: ${e.message}", e) }
        }
    }

    private fun loadAppUsageToday() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.app_usage_today", null) ?: return
        try {
            val json = org.json.JSONObject(raw)
            appUsageToday.clear()
            json.keys().forEach { key -> appUsageToday[key] = json.getLong(key) }
        } catch (e: Exception) { Log.e("ArbainService", "loadAppUsageToday error: ${e.message}") }
    }

    private fun loadAppTimeLimits() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.app_time_limits", null) ?: return
        try {
            val json = JSONObject(raw)
            appTimeLimits.clear()
            json.keys().forEach { key ->
                try { appTimeLimits[key] = json.getInt(key) } catch (e: Exception) {
                    try { appTimeLimits[key] = json.getDouble(key).toInt() } catch (e2: Exception) {}
                }
            }
        } catch (e: Exception) { Log.e("ArbainService", "loadAppTimeLimits error: ${e.message}") }
    }

    private fun checkAndResetDaily() {
        val today = java.util.Calendar.getInstance().get(java.util.Calendar.DAY_OF_YEAR)
        if (lastResetDay != today) {
            appUsageToday.clear()
            lastResetDay = today
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.app_usage_today", "").apply()
            Log.d("ArbainService", "Daily usage reset")
        }
    }

    private fun trackAppUsage(packageName: String) {
        val now = System.currentTimeMillis()
        if (currentAppPackage.isNotEmpty() && currentAppPackage != packageName) {
            val duration = now - currentAppStart
            if (duration > 0) {
                appUsageToday[currentAppPackage] = (appUsageToday[currentAppPackage] ?: 0L) + duration
            }
        }
        currentAppPackage = packageName
        currentAppStart = now
        val prefsUsage = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val usageJson = org.json.JSONObject()
        appUsageToday.forEach { (k, v) -> usageJson.put(k, v) }
        prefsUsage.edit().putString("flutter.app_usage_today", usageJson.toString()).apply()
    }

    private fun isOverTimeLimit(packageName: String): Boolean {
        val today = arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta")).get(java.util.Calendar.DAY_OF_WEEK) - 1]
        val limitMinutes = appTimeLimits["$packageName.$today"] ?: appTimeLimits[packageName] ?: return false
        val savedMs = appUsageToday[packageName] ?: 0L
        val currentMs = if (currentAppPackage == packageName) System.currentTimeMillis() - currentAppStart else 0L
        val totalMs = savedMs + currentMs
        return (totalMs / 60000) >= limitMinutes
    }

    private fun loadBlockedApps() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.blocked_apps", null)
        val apps = mutableSetOf<String>()
        if (raw != null) {
            val cleaned = raw.removePrefix("[").removeSuffix("]")
            if (cleaned.isNotEmpty()) {
                cleaned.split(",").forEach { apps.add(it.trim().removeSurrounding("\"")) }
            }
        }
        blockedApps = apps
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        Log.d("ArbainService", "onAccessibilityEvent fired! pkg=${event?.packageName}")
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (!prefs.getBoolean("flutter.is_sleep", false)) {
                prefs.edit().putBoolean("flutter.is_restricted", false).apply()
            }
            return
        }
        if (packageName.contains("launcher") || packageName.contains("home")) {
            trackAppUsage("")
            return
        }
        checkAndResetDaily()
        trackAppUsage(packageName)
        loadAppTimeLimits()
        Log.d("ArbainService", "checking: pkg=$packageName blocked=${blockedApps.contains(packageName)}")
        val prefs2 = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isNgaji2 = prefs2.getBoolean("flutter.is_ngaji", false)
        val isBrowser2 = BROWSER_PACKAGES.contains(packageName)
        val browserAllowed2 = prefs2.getBoolean("flutter.browser_allowed", false)
        val isBlocked2 = when {
            isNgaji2 && isBrowser2 -> false
            isNgaji2 -> blockedAppsNgaji.contains(packageName)
            isBrowser2 -> !browserAllowed2
            else -> blockedApps.contains(packageName)
        }
        if (isBlocked2 || isOverTimeLimit(packageName)) {
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
            android.view.WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
            android.view.WindowManager.LayoutParams.FLAG_FULLSCREEN or
            android.view.WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            android.view.WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS,
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
        handler.post {
            if (sleepOverlayView == null) {
                wm.addView(layout, params)
                sleepOverlayView = layout
                layout.systemUiVisibility = android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or
                    android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            }
        }
    }

    private fun hideSleepOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
        handler.post { sleepOverlayView?.let { try { wm.removeView(it) } catch (e: Exception) {}; sleepOverlayView = null } }
    }

    private fun pollSchedules() {
        thread {
            try {
                Log.d("ArbainService", "pollSchedules called")
                val nowDebug = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
                Log.d("ArbainService", "day=${arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[nowDebug.get(java.util.Calendar.DAY_OF_WEEK)-1]}, min=${nowDebug.get(java.util.Calendar.HOUR_OF_DAY)*60+nowDebug.get(java.util.Calendar.MINUTE)}")
                val url = URL("https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/schedules?key=$API_KEY")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                conn.connectTimeout = 5000
                conn.readTimeout = 5000
                if (conn.responseCode == 200) {
                    val response = conn.inputStream.bufferedReader().readText()
                    val json = JSONObject(response)
                    val docs = json.optJSONArray("documents") ?: run {
                        hideSleepOverlay()
                        val p = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        p.edit().putBoolean("flutter.is_sleep", false).apply()
                        p.edit().putBoolean("flutter.is_restricted", false).apply()
                        p.edit().putBoolean("flutter.is_ngaji", false).apply()
                        return@thread
                    }
                    val now = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
                    val currentDay = arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[now.get(java.util.Calendar.DAY_OF_WEEK) - 1]
                    val currentMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 + now.get(java.util.Calendar.MINUTE)
                    var shouldSleep = false
                    var shouldNgaji = false
                    for (i in 0 until docs.length()) {
                        val fields = docs.getJSONObject(i).optJSONObject("fields") ?: continue
                        val isActive = fields.optJSONObject("isActive")?.optBoolean("booleanValue") ?: false
                        if (!isActive) continue
                        val scheduleType = fields.optJSONObject("type")?.optString("stringValue") ?: "sleep"
                        val daysArr = fields.optJSONObject("days")?.optJSONObject("arrayValue")?.optJSONArray("values") ?: continue
                        val days = mutableListOf<String>()
                        for (j in 0 until daysArr.length()) { days.add(daysArr.getJSONObject(j).optString("stringValue")) }
                        if (!days.contains(currentDay)) continue
                        val startTime = fields.optJSONObject("startTime")?.optString("stringValue") ?: continue
                        val endTime = fields.optJSONObject("endTime")?.optString("stringValue") ?: continue
                        val startMinutes = startTime.split(":")[0].toInt() * 60 + startTime.split(":")[1].toInt()
                        val endMinutes = endTime.split(":")[0].toInt() * 60 + endTime.split(":")[1].toInt()
                        val inSchedule = if (startMinutes <= endMinutes) currentMinutes >= startMinutes && currentMinutes < endMinutes else currentMinutes >= startMinutes || currentMinutes < endMinutes
                        Log.d("ArbainService", "type=$scheduleType day=$currentDay start=$startMinutes end=$endMinutes cur=$currentMinutes in=$inSchedule")
                        if (inSchedule && scheduleType == "sleep") shouldSleep = true
                        if (inSchedule && scheduleType == "ngaji") {
                            shouldNgaji = true
                            val appsArr = fields.optJSONObject("blockedAppsNgaji")?.optJSONObject("arrayValue")?.optJSONArray("values")
                            val newBlockedNgaji = mutableSetOf<String>()
                            if (appsArr != null) {
                                for (k in 0 until appsArr.length()) {
                                    newBlockedNgaji.add(appsArr.getJSONObject(k).optString("stringValue"))
                                }
                            }
                            blockedAppsNgaji = newBlockedNgaji
                        }
                    }
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("flutter.is_ngaji", shouldNgaji).apply()
                    if (shouldSleep) {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                        val admin = android.content.ComponentName(this, ArbainDeviceAdminReceiver::class.java)
                        if (dpm.isAdminActive(admin)) {
                            showSleepOverlay()
                            Log.d("ArbainService", "isAdminActive=true, calling lockNow")
                            handler.post {
                                try { dpm.lockNow(); Log.d("ArbainService", "lockNow called") }
                                catch (ex: Exception) { Log.e("ArbainService", "lockNow error: ${ex.message}") }
                            }
                        } else { Log.d("ArbainService", "isAdminActive=FALSE") }
                        prefs.edit().putBoolean("flutter.is_sleep", true).apply()
                        prefs.edit().putBoolean("flutter.is_restricted", true).apply()
                    } else {
                        prefs.edit().putBoolean("flutter.is_sleep", false).apply()
                        hideSleepOverlay()
                        prefs.edit().putBoolean("flutter.is_restricted", false).apply()
                    }
                }
                conn.disconnect()
            } catch (e: Exception) { Log.e("ArbainService", "pollSchedules error: ${e.message}", e) }
        }
    }

    override fun onInterrupt() {}
}










