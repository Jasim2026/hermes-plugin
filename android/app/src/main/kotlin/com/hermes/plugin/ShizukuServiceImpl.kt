package com.hermes.plugin

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import rikka.shizuku.Shizuku
import rikka.shizuku.Shizuku.OnRequestPermissionResultListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader

class ShizukuService(private val context: Context) : OnRequestPermissionResultListener {

    companion object {
        private const val CHANNEL = "com.hermes.plugin/shizuku"
        private const val PERMISSION_REQUEST_CODE = 1001

        // Command allowlist — only pre-approved commands
        private val ALLOWED_COMMANDS = setOf(
            "screencap", "pm", "settings", "input", "dumpsys",
            "am", "wm", "getprop", "ls", "cat", "id", "whoami",
            "rm"
        )

        // Path allowlist — only app-specific directories
        private val ALLOWED_READ_PATHS = setOf(
            "/sdcard/hermes_plugin/",
            "/sdcard/hermes_screenshot.png"
        )

        // Paths that rm is allowed to delete
        private val ALLOWED_RM_PATHS = setOf(
            "/sdcard/hermes_screenshot.png"
        )

        // Shell metacharacters that enable injection
        private val SHELL_META = setOf(';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>', '\n', '\r')
    }

    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())
    var isConnected = false
        private set
    var isAuthorized = false
        private set

    fun initChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkShizukuRunning" -> result.success(checkShizukuRunning())
                "checkShizukuPermission" -> result.success(isAuthorized)
                "requestPermission" -> {
                    requestPermission()
                    result.success(true)
                }
                "execCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    // Run on background thread to avoid ANR (process.waitFor blocks)
                    Thread {
                        val execResult = execCommand(command)
                        handler.post { result.success(execResult) }
                    }.start()
                }
                "readFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val resultPath = readFile(path)
                    result.success(resultPath)
                }
                "setVolume" -> {
                    val stream = call.argument<Int>("stream") ?: AudioManager.STREAM_MUSIC
                    val level = call.argument<Int>("level") ?: 0
                    result.success(setVolume(stream, level))
                }
                "getVolume" -> {
                    val stream = call.argument<Int>("stream") ?: AudioManager.STREAM_MUSIC
                    result.success(getVolume(stream))
                }
                "setRingerMode" -> {
                    val mode = call.argument<Int>("mode") ?: AudioManager.RINGER_MODE_NORMAL
                    result.success(setRingerMode(mode))
                }
                "getRingerMode" -> result.success(getRingerMode())
                "getDeviceInfo" -> result.success(getDeviceInfo())
                else -> result.notImplemented()
            }
        }
    }

    fun init() {
        try {
            Shizuku.addRequestPermissionResultListener(this)
            isConnected = checkShizukuRunning()
            if (isConnected) {
                isAuthorized = Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED
            }
        } catch (e: Exception) {
            isConnected = false
            isAuthorized = false
        }
    }

    private fun checkShizukuRunning(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Exception) {
            false
        }
    }

    fun requestPermission() {
        if (Shizuku.shouldShowRequestPermissionRationale()) {
            // User denied permanently
            return
        }
        Shizuku.requestPermission(PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
        if (requestCode == PERMISSION_REQUEST_CODE) {
            isAuthorized = grantResult == android.content.pm.PackageManager.PERMISSION_GRANTED
            handler.post {
                channel?.invokeMethod("onShizukuEvent", mapOf(
                    "type" to "permission",
                    "message" to if (isAuthorized) "granted" else "denied"
                ))
            }
        }
    }

    private fun execCommand(command: String): String? {
        // Validate: reject shell metacharacters
        if (command.any { it in SHELL_META }) {
            return "ERROR:forbidden characters in command"
        }

        // Validate: first token must be an allowed command
        val parts = command.trim().split("\\s+".toRegex())
        if (parts.isEmpty()) return "ERROR:empty command"
        if (parts[0] !in ALLOWED_COMMANDS) {
            return "ERROR:command not allowed: ${parts[0]}"
        }

        // Validate rm: target must be in allowed paths
        if (parts[0] == "rm" && parts.size >= 2) {
            val target = try {
                java.io.File(parts[1]).canonicalPath
            } catch (e: Exception) {
                return "ERROR:invalid path"
            }
            if (target !in ALLOWED_RM_PATHS) {
                return "ERROR:rm not allowed for: $target"
            }
        }

        return try {
            // Use List<String> exec (no shell) — prevents injection
            val process = Runtime.getRuntime().exec(parts.toTypedArray())
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readText()
            process.waitFor()
            output
        } catch (e: Exception) {
            e.message
        }
    }

    private fun readFile(path: String): String? {
        // Validate path — must be in allowed directories
        val canonicalPath = try {
            java.io.File(path).canonicalPath
        } catch (e: Exception) {
            return null
        }

        val allowed = ALLOWED_READ_PATHS.any { canonicalPath.startsWith(it) }
        if (!allowed) return null

        return try {
            if (java.io.File(canonicalPath).exists()) canonicalPath else null
        } catch (e: Exception) {
            null
        }
    }

    private fun setVolume(stream: Int, level: Int): Boolean {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setStreamVolume(stream, level, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun getVolume(stream: Int): Int {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.getStreamVolume(stream)
        } catch (e: Exception) {
            -1
        }
    }

    private fun setRingerMode(mode: Int): Boolean {
        return try {
            // Use Shizuku shell command for ringer mode (needs elevated privileges)
            val cmd = when (mode) {
                0 -> "cmd audio set-ringer-mode 0"  // silent
                1 -> "cmd audio set-ringer-mode 1"  // vibrate
                2 -> "cmd audio set-ringer-mode 2"  // normal
                else -> return false
            }
            val process = Runtime.getRuntime().exec(cmd.trim().split("\\s+".toRegex()).toTypedArray())
            process.waitFor()
            process.exitValue() == 0
        } catch (e: Exception) {
            // Fallback to AudioManager (may fail without DND permission)
            try {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.ringerMode = mode
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun getRingerMode(): Int {
        return try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.ringerMode
        } catch (e: Exception) {
            -1
        }
    }

    private fun getDeviceInfo(): Map<String, String?> {
        return mapOf(
            "model" to android.os.Build.MODEL,
            "manufacturer" to android.os.Build.MANUFACTURER,
            "device" to android.os.Build.DEVICE,
            "androidVersion" to android.os.Build.VERSION.RELEASE,
            "sdkVersion" to android.os.Build.VERSION.SDK_INT.toString(),
            "product" to android.os.Build.PRODUCT
        )
    }

    fun destroy() {
        Shizuku.removeRequestPermissionResultListener(this)
        channel?.setMethodCallHandler(null)
    }
}
