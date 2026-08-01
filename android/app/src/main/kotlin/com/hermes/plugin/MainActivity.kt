package com.hermes.plugin

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.hermes.plugin/lifecycle"
    private var shizukuService: ShizukuService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize Shizuku service
        shizukuService = ShizukuService(this).apply {
            initChannel(flutterEngine)
            init()
        }

        // Initialize accessibility service channel
        val accessibilityService = HermesAccessibilityService.instance
        accessibilityService?.initChannel(flutterEngine)

        // Lifecycle channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAccessibilityService" -> {
                        result.success(HermesAccessibilityService.instance != null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register Shizuku binder death listener
        try {
            rikka.shizuku.Shizuku.addBinderReceivedListener(binderReceivedListener)
            rikka.shizuku.Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Exception) {
            // Shizuku not available
        }
    }

    override fun onDestroy() {
        shizukuService?.destroy()
        try {
            rikka.shizuku.Shizuku.removeBinderReceivedListener(binderReceivedListener)
            rikka.shizuku.Shizuku.removeBinderDeadListener(binderDeadListener)
        } catch (e: Exception) {
            // Shizuku not available
        }
        super.onDestroy()
    }

    private val binderReceivedListener = rikka.shizuku.Shizuku.OnBinderReceivedListener {
        shizukuService?.init()
    }

    private val binderDeadListener = rikka.shizuku.Shizuku.OnBinderDeadListener {
        // Shizuku died
    }
}
