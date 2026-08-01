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
                    val execResult = execCommand(command)
                    result.success(execResult)
                }
                "readFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    val bytes = readFile(path)
                    result.success(bytes)
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
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readText()
            process.waitFor()
            output
        } catch (e: Exception) {
            e.message
        }
    }

    private fun readFile(path: String): ByteArray? {
        return try {
            java.io.File(path).readBytes()
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
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.ringerMode = mode
            true
        } catch (e: Exception) {
            false
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
