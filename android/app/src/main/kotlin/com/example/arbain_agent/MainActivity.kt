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
        val serviceIntent = android.content.Intent(this, ArbainForegroundService::class.java)
        startForegroundService(serviceIntent)
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
                    try { startLockTask(); result.success(true) } catch (e: Exception) { result.error("ERROR", e.message, null) }
                }
                "stopLockTask" -> {
                    try { stopLockTask(); result.success(true) } catch (e: Exception) { result.error("ERROR", e.message, null) }
                }
                "startAppBlocker" -> {
                    val apps = call.argument<List<String>>("blockedApps") ?: listOf()
                    appBlocker.start(apps)
                    result.success(true)
                }
                "hasAccessibilityService" -> {
                    val enabled = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                    result.success(enabled.contains(packageName))
                }
                "openAccessibilitySettings" -> {
                    val intent = android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                }
                "stopAppBlocker" -> { appBlocker.stop(); result.success(true) }
                "hasUsageAccess" -> {
                    val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                    val time = System.currentTimeMillis()
                    val stats = usageStatsManager.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, time - 1000, time)
                    result.success(stats != null && stats.isNotEmpty())
                }
                "openUsageAccessSettings" -> {
                    val intent = android.content.Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.data = android.net.Uri.parse("package:$packageName")
                    intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                    try { startActivity(intent) } catch (e: Exception) {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS).apply { flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK })
                    }
                    result.success(true)
                }
                "updateBlockedApps" -> {
                    val apps = call.argument<List<String>>("blockedApps") ?: listOf()
                    appBlocker.updateBlockedApps(apps)
                    result.success(true)
                }
                "getAppUsageMinutesToday" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                    val cal = java.util.Calendar.getInstance()
                    cal.set(java.util.Calendar.HOUR_OF_DAY, 0); cal.set(java.util.Calendar.MINUTE, 0)
                    cal.set(java.util.Calendar.SECOND, 0); cal.set(java.util.Calendar.MILLISECOND, 0)
                    val stats = usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, cal.timeInMillis, System.currentTimeMillis())
                    val minutes = ((stats?.find { it.packageName == pkg }?.totalTimeInForeground ?: 0L) / 1000 / 60).toInt()
                    result.success(minutes)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.arbain_agent/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" -> result.success(android.provider.Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    startActivity(android.content.Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:$packageName")).apply { flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK })
                    result.success(true)
                }
                "hasAccessibilityPermission" -> {
                    val enabled = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
                    result.success(enabled.contains(packageName))
                }
                "hasBatteryOptimizationExemption" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "openBatterySettings" -> {
                    startActivity(android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:$packageName")).apply { flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK })
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}


