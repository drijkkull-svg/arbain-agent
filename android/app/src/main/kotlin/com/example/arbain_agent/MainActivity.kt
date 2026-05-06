package com.example.arbain_agent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.arbain_agent/device_admin"
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private lateinit var appBlocker: AppBlockerService
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        adminComponent = ComponentName(this, ArbainDeviceAdminReceiver::class.java)
        appBlocker = AppBlockerService(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAdminActive" -> result.success(devicePolicyManager.isAdminActive(adminComponent))
                "requestAdminPermission" -> {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                        putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Diperlukan untuk monitoring santri.")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "lockScreen" -> {
                    if (devicePolicyManager.isAdminActive(adminComponent)) {
                        devicePolicyManager.lockNow()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "startLockTask" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "startAppBlocker" -> {
                    val apps = call.argument<List<String>>("blockedApps") ?: listOf()
                    appBlocker.start(apps)
                    result.success(true)
                }
                "hasAccessibilityService" -> {
                    val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                    val time = System.currentTimeMillis()
                    val stats = usageStatsManager.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, time - 1000, time)
                    result.success(stats != null && stats.isNotEmpty())
                }
                "openAccessibilitySettings" -> {
                    val intent = android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                "stopAppBlocker" -> {
                    appBlocker.stop()
                    result.success(true)
                }
                "updateBlockedApps" -> {
                    val apps = call.argument<List<String>>("blockedApps") ?: listOf()
                    ArbainAccessibilityService.blockedApps = apps
                    appBlocker.updateBlockedApps(apps)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}




