package com.example.arbain_agent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.IBinder
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

class ArbainForegroundService : Service() {

    private val db = FirebaseFirestore.getInstance()
    private val auth = FirebaseAuth.getInstance()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channelId = "arbain_channel"
        val channel = NotificationChannel(channelId, "Arbain Agent", NotificationManager.IMPORTANCE_LOW)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Arbain Agent Aktif")
            .setContentText("Monitoring perangkat santri berjalan.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()
        startForeground(1, notification)
        listenFirebase()
        return START_STICKY
    }

    private fun listenFirebase() {
        val uid = auth.currentUser?.uid ?: return
        db.collection("devices").document(uid).addSnapshotListener { snap, _ ->
            if (snap == null || !snap.exists()) return@addSnapshotListener
            val isRestricted = snap.getBoolean("isRestricted") ?: false
            val blockedApps = snap.get("blockedApps") as? List<*> ?: emptyList<String>()
            if (isRestricted) { lockScreen() }
            saveBlockedApps(blockedApps.map { it.toString() })
        }
    }

    private fun lockScreen() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, ArbainDeviceAdminReceiver::class.java)
        if (dpm.isAdminActive(admin)) { dpm.lockNow() }
    }

    private fun saveBlockedApps(apps: List<String>) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val json = "[" + apps.joinToString(",") { "\"\"" } + "]"
        prefs.edit().putString("flutter.blocked_apps", json).apply()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
