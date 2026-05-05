package com.example.arbain_agent

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class ArbainDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
    }
    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
    }
}
