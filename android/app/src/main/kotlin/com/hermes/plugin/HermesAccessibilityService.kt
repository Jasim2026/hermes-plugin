package com.hermes.plugin

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class HermesAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL = "com.hermes.plugin/accessibility"
        var instance: HermesAccessibilityService? = null
            private set
        private var pendingEngine: FlutterEngine? = null

        fun setPendingEngine(engine: FlutterEngine) {
            pendingEngine = engine
            instance?.let { it.initChannel(engine); pendingEngine = null }
        }
    }

    private var channel: MethodChannel? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        pendingEngine?.let { initChannel(it); pendingEngine = null }
    }

    fun initChannel(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkAccessibilityEnabled" -> result.success(true)
                "openAccessibilitySettings" -> {
                    startActivity(Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(true)
                }
                "tap" -> {
                    val x = call.argument<Number>("x")?.toFloat() ?: 0f
                    val y = call.argument<Number>("y")?.toFloat() ?: 0f
                    result.success(performTap(x, y))
                }
                "longPress" -> {
                    val x = call.argument<Number>("x")?.toFloat() ?: 0f
                    val y = call.argument<Number>("y")?.toFloat() ?: 0f
                    result.success(performLongPress(x, y))
                }
                "swipe" -> {
                    val x1 = call.argument<Number>("x1")?.toFloat() ?: 0f
                    val y1 = call.argument<Number>("y1")?.toFloat() ?: 0f
                    val x2 = call.argument<Number>("x2")?.toFloat() ?: 0f
                    val y2 = call.argument<Number>("y2")?.toFloat() ?: 0f
                    val duration = call.argument<Number>("durationMs")?.toInt() ?: 300
                    result.success(performSwipe(x1, y1, x2, y2, duration))
                }
                "scroll" -> {
                    val direction = call.argument<String>("direction") ?: "down"
                    val distance = call.argument<Number>("distance")?.toFloat() ?: 500f
                    result.success(performScroll(direction, distance))
                }
                "typeText" -> {
                    val text = call.argument<String>("text") ?: ""
                    result.success(performTypeText(text))
                }
                "pressBack" -> result.success(performGlobalAction(GLOBAL_ACTION_BACK))
                "pressHome" -> result.success(performGlobalAction(GLOBAL_ACTION_HOME))
                "pressRecent" -> result.success(performGlobalAction(GLOBAL_ACTION_RECENTS))
                "getScreenContent" -> result.success(getScreenContent())
                "findElement" -> {
                    val text = call.argument<String>("text") ?: ""
                    result.success(findElementByText(text))
                }
                "clickElement" -> {
                    val nodeId = call.argument<String>("nodeId") ?: ""
                    result.success(clickNodeById(nodeId))
                }
                "getInstalledApps" -> result.success(getInstalledApps())
                "openApp" -> {
                    val pkg = call.argument<String>("packageName") ?: ""
                    result.success(openAppByPackage(pkg))
                }
                "screenOn" -> result.success(screenOn())
                "screenOff" -> result.success(screenOff())
                "takeScreenshot" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        takeScreenshot(
                            android.view.Display.DEFAULT_DISPLAY,
                            { it.run() },
                            object : AccessibilityService.TakeScreenshotCallback {
                                override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                                    try {
                                        val buffer = result.hardwareBuffer
                                        val bitmap = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                                        buffer?.close()
                                        if (bitmap != null) {
                                            val stream = java.io.ByteArrayOutputStream()
                                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                                            bitmap.recycle()
                                            val base64 = android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
                                            handler.post { channel?.invokeMethod("screenshotResult", base64) }
                                        } else {
                                            handler.post { channel?.invokeMethod("screenshotError", "bitmap is null") }
                                        }
                                    } catch (e: Exception) {
                                        handler.post { channel?.invokeMethod("screenshotError", e.message) }
                                    }
                                }
                                override fun onError(errorCode: Int) {
                                    handler.post { channel?.invokeMethod("screenshotError", "errorCode: $errorCode") }
                                }
                            }
                        )
                        result.success(true)
                    } else {
                        result.error("API_TOO_LOW", "takeScreenshot requires API 30+", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event?.let {
            val args = hashMapOf<String, Any?>(
                "eventType" to it.eventType.toString(),
                "packageName" to it.packageName?.toString(),
                "className" to it.className?.toString(),
                "text" to it.text?.joinToString(" "),
                "description" to it.contentDescription?.toString()
            )
            channel?.invokeMethod("onAccessibilityEvent", args)
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        channel?.setMethodCallHandler(null)
        super.onDestroy()
    }

    private fun performTap(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun performLongPress(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 1000))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun performSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Int): Boolean {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs.toLong()))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    private fun performScroll(direction: String, distance: Float): Boolean {
        val centerX = resources.displayMetrics.widthPixels / 2f
        val centerY = resources.displayMetrics.heightPixels / 2f

        val (startX, startY, endX, endY) = when (direction) {
            "up" -> listOf(centerX, centerY + distance, centerX, centerY - distance)
            "down" -> listOf(centerX, centerY - distance, centerX, centerY + distance)
            "left" -> listOf(centerX + distance, centerY, centerX - distance, centerY)
            "right" -> listOf(centerX - distance, centerY, centerX + distance, centerY)
            else -> listOf(centerX, centerY + distance, centerX, centerY - distance)
        }

        return performSwipe(startX, startY, endX, endY, 300)
    }

    private fun performTypeText(text: String): Boolean {
        val bundle = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val focusedNode = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        return focusedNode?.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, bundle) ?: false
    }

    private fun getScreenContent(): Map<String, Any?> {
        val rootNode = rootInActiveWindow ?: return mapOf("error" to "No active window")
        return nodeToMap(rootNode)
    }

    private fun nodeToMap(node: AccessibilityNodeInfo, path: String = "0"): Map<String, Any?> {
        val rect = android.graphics.Rect()
        node.getBoundsInScreen(rect)
        val map = mutableMapOf<String, Any?>(
            "className" to node.className?.toString(),
            "text" to node.text?.toString(),
            "contentDescription" to node.contentDescription?.toString(),
            "isClickable" to node.isClickable,
            "isEnabled" to node.isEnabled,
            "bounds" to mapOf("left" to rect.left, "top" to rect.top,
                "right" to rect.right, "bottom" to rect.bottom),
            "nodeId" to path
        )

        val children = mutableListOf<Map<String, Any?>>()
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            children.add(nodeToMap(child, "${path}_${i}"))
            child.recycle()
        }
        if (children.isNotEmpty()) {
            map["children"] = children
        }

        return map
    }

    private fun findElementByText(text: String): Map<String, Any?>? {
        val rootNode = rootInActiveWindow ?: return null
        val nodes = rootNode.findAccessibilityNodeInfosByText(text)
        return if (nodes != null && nodes.isNotEmpty()) {
            val result = nodeToMap(nodes[0])
            for (n in nodes) n.recycle()
            result
        } else {
            null
        }
    }

    private fun clickNodeById(nodeId: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        return clickNodeRecursive(rootNode, nodeId, "0")
    }

    private fun clickNodeRecursive(node: AccessibilityNodeInfo, targetId: String, currentPath: String): Boolean {
        if (currentPath == targetId) {
            return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val childPath = "${currentPath}_${i}"
            if (clickNodeRecursive(child, targetId, childPath)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val packageManager = applicationContext.packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        return packageManager.queryIntentActivities(intent, 0).map { resolveInfo ->
            mapOf(
                "packageName" to resolveInfo.activityInfo.packageName,
                "appName" to resolveInfo.loadLabel(packageManager).toString()
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun screenOn(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            if (pm.isInteractive) return true
            val wakeLock = pm.newWakeLock(
                android.os.PowerManager.FULL_WAKE_LOCK,
                "hermes:screen_on"
            )
            wakeLock.acquire(3000L)
            wakeLock.release()
            true
        } catch (e: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun screenOff(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            if (!pm.isInteractive) return true
            val method = pm.javaClass.getMethod("goToSleep", Long::class.java)
            method.invoke(pm, android.os.SystemClock.uptimeMillis())
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openAppByPackage(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }
}
