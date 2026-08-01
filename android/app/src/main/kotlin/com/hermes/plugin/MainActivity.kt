package com.hermes.plugin

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.hermes.plugin/lifecycle"
    private var shizukuService: ShizukuService? = null
    private companion object {
        const val NOTIFICATION_PERMISSION_CODE = 2001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        startForegroundService(Intent(this, HermesService::class.java))

        shizukuService = ShizukuService(this).apply {
            initChannel(flutterEngine)
            init()
        }

        val accessibilityService = HermesAccessibilityService.instance
        if (accessibilityService != null) {
            accessibilityService.initChannel(flutterEngine)
        } else {
            HermesAccessibilityService.setPendingEngine(flutterEngine)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Existing
                    "getAccessibilityService" -> result.success(HermesAccessibilityService.instance != null)
                    "openAppInfo" -> { openAppInfo(); result.success(true) }
                    "openSettings" -> {
                        val action = call.argument<String>("action") ?: ""
                        val data = call.argument<String>("data") ?: ""
                        openSettings(action, data); result.success(true)
                    }
                    "checkNotificationPermission" -> result.success(isNotificationPermissionGranted())
                    "requestNotificationPermission" -> requestNotificationPermission(result)

                    // Tier 1
                    "getAppState" -> result.success(getAppState())
                    "getDisplayInfo" -> result.success(getDisplayInfo())

                    // Tier 2
                    "uiAutomatorDump" -> {
                        Thread {
                            val dumpResult = uiAutomatorDump()
                            runOnUiThread { result.success(dumpResult) }
                        }.start()
                    }
                    "getInputMethods" -> result.success(getInputMethods())
                    "setInputMethod" -> {
                        val imeId = call.argument<String>("imeId") ?: ""
                        result.success(setInputMethod(imeId))
                    }
                    "clearInputField" -> result.success(clearInputField())

                    // Tier 3
                    "getBatteryInfo" -> result.success(getBatteryInfo())
                    "getMemoryInfo" -> result.success(getMemoryInfo())

                    else -> result.notImplemented()
                }
            }
    }

    // ========================
    // APP STATE DETECTION
    // ========================

    private fun getAppState(): Map<String, Any?> {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val task = am.getRunningTasks(1)?.firstOrNull()
            val topActivity = task?.topActivity
            mapOf(
                "packageName" to topActivity?.packageName,
                "className" to topActivity?.className,
                "taskDescription" to task?.taskDescription?.label?.toString(),
                "baseActivity" to task?.baseActivity?.className
            )
        } catch (e: Exception) {
            mapOf("error" to e.message)
        }
    }

    // ========================
    // DISPLAY INFO
    // ========================

    private fun getDisplayInfo(): Map<String, Any?> {
        val dm = resources.displayMetrics
        val densityDpi = dm.densityDpi
        val density = dm.density
        return mapOf(
            "widthPx" to dm.widthPixels,
            "heightPx" to dm.heightPixels,
            "density" to density,
            "densityDpi" to densityDpi,
            "scaledDensity" to dm.scaledDensity,
            "xDpi" to dm.xdpi,
            "yDpi" to dm.ydpi,
            "androidSdk" to Build.VERSION.SDK_INT
        )
    }

    // ========================
    // UI AUTOMATOR DUMP
    // ========================

    private fun uiAutomatorDump(): Map<String, Any?> {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("uiautomator", "dump", "/dev/tty"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readText()
            process.waitFor()

            // Extract XML from output (uiautomator dumps to stdout when output is /dev/tty)
            val xmlStart = output.indexOf("<?xml")
            val xmlEnd = output.indexOf("</hierarchy>")
            if (xmlStart >= 0 && xmlEnd > xmlStart) {
                val xml = output.substring(xmlStart, xmlEnd + "</hierarchy>".length)
                mapOf("xml" to xml, "success" to true)
            } else {
                // Fallback: try reading from the default dump location
                val fallback = Runtime.getRuntime().exec(arrayOf("cat", "/sdcard/window_dump.xml"))
                val fbReader = BufferedReader(InputStreamReader(fallback.inputStream))
                val fbOutput = fbReader.readText()
                fallback.waitFor()
                if (fbOutput.isNotEmpty()) {
                    mapOf("xml" to fbOutput, "success" to true)
                } else {
                    mapOf("error" to "UI Automator dump failed", "success" to false)
                }
            }
        } catch (e: Exception) {
            mapOf("error" to e.message, "success" to false)
        }
    }

    // ========================
    // INPUT METHOD CONTROL
    // ========================

    private fun getInputMethods(): Map<String, Any?> {
        return try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            val enabledImes = imm.enabledInputMethodList.map { ime ->
                mapOf(
                    "id" to ime.id,
                    "label" to ime.loadLabel(packageManager).toString(),
                    "subtypes" to ime.subtypeCount
                )
            }
            val currentIme = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            mapOf(
                "currentIme" to currentIme,
                "enabledImes" to enabledImes,
                "count" to enabledImes.size
            )
        } catch (e: Exception) {
            mapOf("error" to e.message)
        }
    }

    private fun setInputMethod(imeId: String): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun clearInputField(): Boolean {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val task = am.getRunningTasks(1)?.firstOrNull()
            val topActivity = task?.topActivity ?: return false

            // Send broadcast to accessibility service to clear focused field
            val intent = Intent("com.hermes.plugin.CLEAR_INPUT")
            sendBroadcast(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ========================
    // BATTERY INFO
    // ========================

    private fun getBatteryInfo(): Map<String, Any?> {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val isCharging = bm.isCharging
            mapOf(
                "level" to level,
                "isCharging" to isCharging,
                "status" to when {
                    isCharging -> "charging"
                    level <= 15 -> "low"
                    else -> "discharging"
                }
            )
        } catch (e: Exception) {
            mapOf("error" to e.message)
        }
    }

    // ========================
    // MEMORY INFO
    // ========================

    private fun getMemoryInfo(): Map<String, Any?> {
        return try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            am.getMemoryInfo(memInfo)
            mapOf(
                "totalMem" to memInfo.totalMem,
                "availMem" to memInfo.availMem,
                "usedMem" to (memInfo.totalMem - memInfo.availMem),
                "lowMemory" to memInfo.lowMemory,
                "threshold" to memInfo.threshold
            )
        } catch (e: Exception) {
            mapOf("error" to e.message)
        }
    }

    // ========================
    // EXISTING METHODS
    // ========================

    private fun openAppInfo() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openSettings(action: String, data: String) {
        val intent = Intent(action).apply {
            if (data.isNotEmpty()) this.data = Uri.parse(data)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun isNotificationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: io.flutter.plugin.common.MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) { result.success(true); return }
        if (isNotificationPermissionGranted()) { result.success(true); return }
        notificationPermissionResult = result
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_CODE)
    }

    private var notificationPermissionResult: io.flutter.plugin.common.MethodChannel.Result? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            rikka.shizuku.Shizuku.addBinderReceivedListener(binderReceivedListener)
            rikka.shizuku.Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        shizukuService?.destroy()
        try {
            rikka.shizuku.Shizuku.removeBinderReceivedListener(binderReceivedListener)
            rikka.shizuku.Shizuku.removeBinderDeadListener(binderDeadListener)
        } catch (e: Exception) {}
        super.onDestroy()
    }

    private val binderReceivedListener = rikka.shizuku.Shizuku.OnBinderReceivedListener { shizukuService?.init() }
    private val binderDeadListener = rikka.shizuku.Shizuku.OnBinderDeadListener {}
}
