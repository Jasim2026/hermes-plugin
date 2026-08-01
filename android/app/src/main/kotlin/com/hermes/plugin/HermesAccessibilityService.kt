package com.hermes.plugin

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class HermesAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL = "com.hermes.plugin/accessibility"
        var instance: HermesAccessibilityService? = null
            private set
    }

    private var channel: MethodChannel? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
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
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    result.success(performTap(x, y))
                }
                "longPress" -> {
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    result.success(performLongPress(x, y))
                }
                "swipe" -> {
                    val x1 = call.argument<Double>("x1")?.toFloat() ?: 0f
                    val y1 = call.argument<Double>("y1")?.toFloat() ?: 0f
                    val x2 = call.argument<Double>("x2")?.toFloat() ?: 0f
                    val y2 = call.argument<Double>("y2")?.toFloat() ?: 0f
                    val duration = call.argument<Int>("durationMs") ?: 300
                    result.success(performSwipe(x1, y1, x2, y2, duration))
                }
                "scroll" -> {
                    val direction = call.argument<String>("direction") ?: "down"
                    val distance = call.argument<Double>("distance")?.toFloat() ?: 500f
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

    private fun nodeToMap(node: AccessibilityNodeInfo): Map<String, Any?> {
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
            "nodeId" to node.hashCode().toString()
        )

        val children = mutableListOf<Map<String, Any?>>()
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            children.add(nodeToMap(child))
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
            nodeToMap(nodes[0])
        } else {
            null
        }
    }

    private fun clickNodeById(nodeId: String): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        return clickNodeRecursive(rootNode, nodeId)
    }

    private fun clickNodeRecursive(node: AccessibilityNodeInfo, targetId: String): Boolean {
        if (node.hashCode().toString() == targetId) {
            return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (clickNodeRecursive(child, targetId)) return true
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
