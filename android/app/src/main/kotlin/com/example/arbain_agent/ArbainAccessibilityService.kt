package com.example.arbain_agent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

class ArbainAccessibilityService : AccessibilityService() {

    private var blockedApps = mutableSetOf<String>()
    private var firestoreListener: ListenerRegistration? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info
        startListeningFirestore()
    }

    private fun startListeningFirestore() {
        val auth = FirebaseAuth.getInstance()
        val uid = auth.currentUser?.uid

        if (uid == null) {
            auth.signInAnonymously().addOnSuccessListener {
                val newUid = auth.currentUser?.uid ?: return@addOnSuccessListener
                listenBlockedApps(newUid)
            }
        } else {
            listenBlockedApps(uid)
        }
    }

    private fun listenBlockedApps(uid: String) {
        val db = FirebaseFirestore.getInstance()
        firestoreListener = db.collection("devices").document(uid)
            .addSnapshotListener { snapshot, error ->
                if (error != null || snapshot == null) return@addSnapshotListener
                val isRestricted = snapshot.getBoolean("isRestricted") ?: false
                if (isRestricted) {
                    @Suppress("UNCHECKED_CAST")
                    val apps = snapshot.get("blockedApps") as? List<String> ?: emptyList()
                    blockedApps = apps.toMutableSet()
                } else {
                    blockedApps = mutableSetOf()
                }
            }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName == applicationContext.packageName) return
        if (blockedApps.contains(packageName)) {
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(homeIntent)
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        firestoreListener?.remove()
    }
}
