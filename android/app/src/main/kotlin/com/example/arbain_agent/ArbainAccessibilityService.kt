package com.example.arbain_agent
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

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
    private var wasRestricted = false
    private var lastBlockedPackage = ""
    private var deviceListener: ListenerRegistration? = null
    private var schedulesListener: ListenerRegistration? = null

    private val BROWSER_PACKAGES = setOf("com.android.chrome", "org.mozilla.firefox", "com.opera.browser", "com.microsoft.emmx")

    private val checkRunnable = object : Runnable {
        override fun run() {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isRestricted = prefs.getBoolean("flutter.is_restricted", false)
            Log.d("ArbainService", "wasRestricted=$wasRestricted isRestricted=$isRestricted")
            if (isRestricted) {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                if (launchIntent != null) {
                    startActivity(launchIntent)
                    handler.postDelayed({
                        val lockIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        }
                        if (lockIntent != null) startActivity(lockIntent)
                    }, 2000)
                }
            }
            wasRestricted = isRestricted
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
            if (shouldBlock && lastBlockedPackage != currentAppPackage) {
                lastBlockedPackage = currentAppPackage
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(homeIntent)
                Log.d("ArbainService", "Closing app: $currentAppPackage")
                handler.postDelayed({ lastBlockedPackage = "" }, 3000)
            }
            handler.postDelayed(this, 1000)
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
        startFirestoreListeners()
        handler.post(checkRunnable)
    }

    private fun getDeviceUid(): String? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getString("flutter.device_uid", null)
    }

    private fun startFirestoreListeners() {
        val uid = getDeviceUid() ?: return
        val db = FirebaseFirestore.getInstance()

        // Realtime listener untuk device document
        deviceListener = db.collection("devices").document(uid)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e("ArbainService", "deviceListener error: ${error.message}")
                    return@addSnapshotListener
                }
                if (snapshot == null || !snapshot.exists()) return@addSnapshotListener
                val data = snapshot.data ?: return@addSnapshotListener
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                // Browser allowed
                val browserAllowed = data["browserAllowed"] as? Boolean ?: false
                prefs.edit().putBoolean("flutter.browser_allowed", browserAllowed).apply()

                // isRestricted
                val isRestricted = data["isRestricted"] as? Boolean ?: false
                prefs.edit().putBoolean("flutter.is_restricted", isRestricted).apply()
                Log.d("ArbainService", "deviceListener: isRestricted=$isRestricted")

                // blockedApps
                @Suppress("UNCHECKED_CAST")
                val newApps = (data["blockedApps"] as? List<String> ?: emptyList()).toMutableSet()
                blockedApps = newApps
                Log.d("ArbainService", "deviceListener: blockedApps=$newApps")

                // appTimeLimits
                @Suppress("UNCHECKED_CAST")
                val timeLimits = data["appTimeLimits"] as? Map<String, Any> ?: emptyMap()
                appTimeLimits.clear()
                fun flattenMap(map: Map<String, Any>, prefix: String) {
                    map.forEach { (key, value) ->
                        val fullKey = if (prefix.isEmpty()) key else "$prefix.$key"
                        when (value) {
                            is Map<*, *> -> @Suppress("UNCHECKED_CAST") flattenMap(value as Map<String, Any>, fullKey)
                            is Long -> if (value > 0) appTimeLimits[fullKey] = value.toInt()
                            is Double -> if (value > 0) appTimeLimits[fullKey] = value.toInt()
                        }
                    }
                }
                flattenMap(timeLimits, "")
            }

        // Realtime listener untuk schedules
        schedulesListener = db.collection("schedules")
            .addSnapshotListener { snapshots, error ->
                if (error != null) {
                    Log.e("ArbainService", "schedulesListener error: ${error.message}")
                    return@addSnapshotListener
                }
                if (snapshots == null) return@addSnapshotListener
                Log.d("ArbainService", "schedulesListener: ${snapshots.size()} schedules")

                val now = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Jakarta"))
                val currentDay = arrayOf("Minggu","Senin","Selasa","Rabu","Kamis","Jumat","Sabtu")[now.get(java.util.Calendar.DAY_OF_WEEK) - 1]
                val currentMinutes = now.get(java.util.Calendar.HOUR_OF_DAY) * 60 + now.get(java.util.Calendar.MINUTE)

                var shouldSleep = false
                var shouldNgaji = false

                for (doc in snapshots.documents) {
                    val data = doc.data ?: continue
                    val isActive = data["isActive"] as? Boolean ?: false
                    if (!isActive) continue
                    val scheduleType = data["type"] as? String ?: "sleep"
                    @Suppress("UNCHECKED_CAST")
                    val days = data["days"] as? List<String> ?: continue
                    if (!days.contains(currentDay)) continue
                    val startTime = data["startTime"] as? String ?: continue
                    val endTime = data["endTime"] as? String ?: continue
                    val startMinutes = startTime.split(":")[0].toInt() * 60 + startTime.split(":")[1].toInt()
                    val endMinutes = endTime.split(":")[0].toInt() * 60 + endTime.split(":")[1].toInt()
                    val inSchedule = if (startMinutes <= endMinutes) currentMinutes >= startMinutes && currentMinutes < endMinutes else currentMinutes >= startMinutes || currentMinutes < endMinutes
                    Log.d("ArbainService", "type=$scheduleType day=$currentDay start=$startMinutes end=$endMinutes cur=$currentMinutes in=$inSchedule")
                    if (inSchedule && scheduleType == "sleep") shouldSleep = true
                    if (inSchedule && scheduleType == "ngaji") {
                        shouldNgaji = true
                        @Suppress("UNCHECKED_CAST")
                        val appsNgaji = data["blockedAppsNgaji"] as? List<String> ?: emptyList()
                        if (appsNgaji.isNotEmpty()) blockedAppsNgaji = appsNgaji.toMutableSet()
                    }
                }

                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("flutter.is_ngaji", shouldNgaji).apply()

                if (shouldSleep) {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as android.app.admin.DevicePolicyManager
                    val admin = android.content.ComponentName(this, ArbainDeviceAdminReceiver::class.java)
                    if (dpm.isAdminActive(admin)) {
                        showSleepOverlay()
                        handler.post {
                            try { dpm.lockNow() } catch (ex: Exception) { Log.e("ArbainService", "lockNow error: ${ex.message}") }
                        }
                    }
                    prefs.edit().putBoolean("flutter.is_sleep", true).apply()
                    prefs.edit().putBoolean("flutter.is_restricted", true).apply()
                } else {
                    prefs.edit().putBoolean("flutter.is_sleep", false).apply()
                    hideSleepOverlay()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        deviceListener?.remove()
        schedulesListener?.remove()
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
            val json = org.json.JSONObject(raw)
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
        if (event == null) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handler.postDelayed({
                val allWindows = windows ?: return@postDelayed
                for (window in allWindows) {
                    val root = window.root ?: continue
                    fun findAndClick(node: android.view.accessibility.AccessibilityNodeInfo?) {
                        if (node == null) return
                        val text = node.text?.toString() ?: ""
                        if ((text == "Mengerti" || text == "Got it" || text == "OK") && node.isClickable) {
                            node.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
                            return
                        }
                        for (i in 0 until node.childCount) findAndClick(node.getChild(i))
                    }
                    findAndClick(root)
                }
            }, 500)
        }
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) return
        if (packageName.contains("launcher") || packageName.contains("home")) {
            trackAppUsage("")
            return
        }
        checkAndResetDaily()
        trackAppUsage(packageName)
        loadAppTimeLimits()
        val prefs2 = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isNgaji2 = prefs2.getBoolean("flutter.is_ngaji", false)
        val isBrowser2 = BROWSER_PACKAGES.contains(packageName)
        val browserAllowed2 = prefs2.getBoolean("flutter.browser_allowed", false)
        val isBlocked2 = when {
            isNgaji2 && isBrowser2 -> false
            isNgaji2 -> blockedAppsNgaji.contains(packageName) || blockedApps.contains(packageName)
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

    private fun showBlockedOverlay(packageName: String) {
        val wm = getSystemService(WINDOW_SERVICE) as android.view.WindowManager
        val params = android.view.WindowManager.LayoutParams(
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.MATCH_PARENT,
            android.view.WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            android.view.WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            android.graphics.PixelFormat.TRANSLUCENT
        )
        val inflater = android.view.LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.overlay_blocked, null)
        wm.addView(view, params)
        handler.postDelayed({
            try { wm.removeView(view) } catch (e: Exception) {}
            performGlobalAction(GLOBAL_ACTION_HOME)
        }, 1000)
        view.setOnClickListener {
            try { wm.removeView(view) } catch (e: Exception) {}
            performGlobalAction(GLOBAL_ACTION_HOME)
        }
    }

    override fun onInterrupt() {}
}