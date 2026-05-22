package com.example.arbain_agent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.Ringtone
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.arbain_agent/device_admin"
    private var currentCamera: android.hardware.camera2.CameraDevice? = null
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
                "getUsageStats" -> {
                    val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
                    val now = System.currentTimeMillis()
                    val start = now - 24 * 60 * 60 * 1000
                    val stats = usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, start, now)
                    val list = stats
                        ?.filter { it.totalTimeInForeground > 0 }
                        ?.map { mapOf("packageName" to it.packageName, "totalMinutes" to (it.totalTimeInForeground / 1000 / 60).toInt()) }
                        ?: listOf()
                    result.success(list)
                }
                                "playAlarm" -> {
                    try {
                        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        val ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
                        ringtone.play()
                        // Simpan referensi buat stop
                        MainActivity.currentRingtone = ringtone
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "stopAlarm" -> {
                    try {
                        MainActivity.currentRingtone?.stop()
                        MainActivity.currentRingtone = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "blockUninstall" -> {
                    try {
                        if (devicePolicyManager.isAdminActive(adminComponent)) {
                            devicePolicyManager.setUninstallBlocked(adminComponent, packageName, true)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "unblockUninstall" -> {
                    try {
                        if (devicePolicyManager.isAdminActive(adminComponent)) {
                            devicePolicyManager.setUninstallBlocked(adminComponent, packageName, false)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "isUninstallBlocked" -> {
                    try {
                        if (devicePolicyManager.isAdminActive(adminComponent)) {
                            result.success(devicePolicyManager.isUninstallBlocked(adminComponent, packageName))
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "takeSnapshot" -> {
                    val type = call.argument<String>("type") ?: "front"
                    takeSilentSnapshot(type, result)
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

    companion object {
        var currentRingtone: Ringtone? = null
    }


    private fun takeSilentSnapshot(type: String, result: MethodChannel.Result) {
        try {
            val cameraManager = getSystemService(CAMERA_SERVICE) as android.hardware.camera2.CameraManager
            val cameraList = cameraManager.cameraIdList
            var targetId = cameraList[0]
            for (id in cameraList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = chars.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING)
                if (type == "front" && facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_FRONT) {
                    targetId = id; break
                } else if (type == "back" && facing == android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK) {
                    targetId = id; break
                }
            }
            val outputFile = java.io.File(cacheDir, "snapshot_${System.currentTimeMillis()}.jpg")
            val imageReader = android.media.ImageReader.newInstance(640, 480, android.graphics.ImageFormat.JPEG, 1)
            val handlerThread = android.os.HandlerThread("CameraSnapshot")
            handlerThread.start()
            val handler = android.os.Handler(handlerThread.looper)
            imageReader.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage()
                if (image != null) {
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    outputFile.writeBytes(bytes)
                    image.close()
                    runOnUiThread { result.success(outputFile.absolutePath) }
                } else {
                    runOnUiThread { result.error("NO_IMAGE", "No image captured", null) }
                }
                handlerThread.quitSafely()
            }, handler)
            val stateCallback = object : android.hardware.camera2.CameraDevice.StateCallback() {
                override fun onOpened(camera: android.hardware.camera2.CameraDevice) {
                        currentCamera = camera
                    val captureRequest = camera.createCaptureRequest(android.hardware.camera2.CameraDevice.TEMPLATE_STILL_CAPTURE)
                    captureRequest.addTarget(imageReader.surface)
                    camera.createCaptureSession(listOf(imageReader.surface), object : android.hardware.camera2.CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: android.hardware.camera2.CameraCaptureSession) {
                            session.capture(captureRequest.build(), object : android.hardware.camera2.CameraCaptureSession.CaptureCallback() {
                                override fun onCaptureCompleted(s: android.hardware.camera2.CameraCaptureSession, r: android.hardware.camera2.CaptureRequest, res: android.hardware.camera2.TotalCaptureResult) {
                                    camera.close()
                                }
                            }, handler)
                        }
                        override fun onConfigureFailed(session: android.hardware.camera2.CameraCaptureSession) {
                            camera.close()
                            runOnUiThread { result.error("CONFIG_FAILED", "Camera config failed", null) }
                        }
                    }, handler)
                }
                override fun onDisconnected(camera: android.hardware.camera2.CameraDevice) { camera.close(); currentCamera = null }
                override fun onError(camera: android.hardware.camera2.CameraDevice, error: Int) {
                    camera.close()
                    currentCamera = null
                    runOnUiThread { result.error("CAMERA_ERROR", "Camera error: $error", null) }
                }
            }
            if (androidx.core.app.ActivityCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                try { currentCamera?.close(); currentCamera = null } catch (e: Exception) {}
                Thread.sleep(300) // tunggu kamera benar-benar tertutup
                cameraManager.openCamera(targetId, stateCallback, handler)
            } else {
                result.error("NO_PERMISSION", "Camera permission not granted", null)
            }
        } catch (e: Exception) {
            result.error("EXCEPTION", e.message, null)
        }
    }

}