package ai.flutterclaw.flutterclaw

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class FlutterClawAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: FlutterClawAccessibilityService? = null

        fun isRunning() = instance != null
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    // ─── Gesture: tap ────────────────────────────────────────────────────────

    fun performTap(x: Float, y: Float, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(false)
            return
        }
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) = callback(true)
            override fun onCancelled(gestureDescription: GestureDescription?) = callback(false)
        }, null)
    }

    // ─── Gesture: swipe ──────────────────────────────────────────────────────

    fun performSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            callback(false)
            return
        }
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.coerceIn(50, 5000))
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) = callback(true)
            override fun onCancelled(gestureDescription: GestureDescription?) = callback(false)
        }, null)
    }

    // ─── Type text into focused field ────────────────────────────────────────

    fun typeText(text: String): Map<String, Any?> {
        val focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return mapOf("success" to false, "message" to "No focused input field. Tap the field first.")
        val bundle = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val ok = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, bundle)
        focused.recycle()
        return if (ok) mapOf("success" to true)
        else mapOf("success" to false, "message" to "ACTION_SET_TEXT failed on focused node.")
    }

    // ─── Find elements ───────────────────────────────────────────────────────

    fun findElements(query: String?, by: String): Map<String, Any?> {
        val rootList = windows?.mapNotNull { it.root } ?: emptyList()
        if (rootList.isEmpty()) {
            val root = rootInActiveWindow
                ?: return mapOf("elements" to emptyList<Any>(), "count" to 0)
            return serializeNodes(collectNodes(root, query, by))
        }
        val allNodes = mutableListOf<AccessibilityNodeInfo>()
        for (root in rootList) {
            allNodes.addAll(collectNodes(root, query, by))
        }
        return serializeNodes(allNodes)
    }

    // ─── Click element ───────────────────────────────────────────────────────

    fun clickElement(query: String, by: String): Map<String, Any?> {
        val rootList = windows?.mapNotNull { it.root } ?: emptyList()
        val searchRoots = if (rootList.isEmpty()) {
            val r = rootInActiveWindow ?: return mapOf("success" to false, "message" to "No active window")
            listOf(r)
        } else rootList

        for (root in searchRoots) {
            val nodes = collectNodes(root, query, by)
            val clickable = nodes.firstOrNull { it.isClickable && it.isEnabled }
                ?: nodes.firstOrNull { it.isEnabled }
            if (clickable != null) {
                val serialized = serializeNode(clickable, 0)
                val ok = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                clickable.recycle()
                return mapOf(
                    "success" to ok,
                    "element" to serialized,
                    "message" to if (ok) null else "ACTION_CLICK returned false"
                )
            }
        }
        return mapOf("success" to false, "message" to "Element not found: $query (by=$by)")
    }

    // ─── Global actions ──────────────────────────────────────────────────────

    fun doGlobalAction(action: String): Boolean {
        val code = when (action) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            else -> return false
        }
        return performGlobalAction(code)
    }

    // ─── Screenshot (API 30+) ────────────────────────────────────────────────

    fun takeScreenshotApi30(callback: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            callback(null)
            return
        }
        try {
            val executor = Executors.newSingleThreadExecutor()
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val bmp = android.graphics.Bitmap.wrapHardwareBuffer(
                            screenshot.hardwareBuffer, screenshot.colorSpace
                        )
                        screenshot.hardwareBuffer.close()
                        if (bmp == null) {
                            callback(null)
                            return
                        }
                        // Copy to software bitmap for PNG encoding
                        val softBmp = bmp.copy(android.graphics.Bitmap.Config.ARGB_8888, false)
                        bmp.recycle()
                        val baos = ByteArrayOutputStream()
                        softBmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, baos)
                        softBmp.recycle()
                        callback(baos.toByteArray())
                    }

                    override fun onFailure(errorCode: Int) {
                        callback(null)
                    }
                }
            )
        } catch (_: Exception) {
            // SecurityException if canTakeScreenshot capability is missing — fall back to PixelCopy
            callback(null)
        }
    }

    // ─── Node traversal helpers ──────────────────────────────────────────────

    private fun collectNodes(
        root: AccessibilityNodeInfo,
        query: String?,
        by: String,
    ): List<AccessibilityNodeInfo> {
        val all = mutableListOf<AccessibilityNodeInfo>()
        collectAll(root, all, depth = 0)
        if (query == null || by == "all") return all

        return when (by) {
            "text" -> all.filter {
                it.text?.toString()?.contains(query, ignoreCase = true) == true
            }
            "id" -> all.filter {
                it.viewIdResourceName?.contains(query, ignoreCase = true) == true
            }
            "description" -> all.filter {
                it.contentDescription?.toString()?.contains(query, ignoreCase = true) == true
            }
            "class" -> all.filter {
                it.className?.toString()?.contains(query, ignoreCase = true) == true
            }
            else -> all
        }
    }

    private fun collectAll(
        node: AccessibilityNodeInfo?,
        result: MutableList<AccessibilityNodeInfo>,
        depth: Int,
    ) {
        if (node == null || result.size >= 200 || depth > 30) return
        result.add(node)
        for (i in 0 until node.childCount) {
            collectAll(node.getChild(i), result, depth + 1)
        }
    }

    private fun serializeNodes(nodes: List<AccessibilityNodeInfo>): Map<String, Any?> {
        // Sort by Y then X (top-to-bottom, left-to-right reading order)
        val sorted = nodes.sortedWith(compareBy({ boundsOf(it).top }, { boundsOf(it).left }))
        val list = sorted.mapIndexed { index, node -> serializeNode(node, index) }
        nodes.forEach { it.recycle() }
        return mapOf("elements" to list, "count" to list.size)
    }

    private fun serializeNode(node: AccessibilityNodeInfo, index: Int): Map<String, Any?> {
        val bounds = boundsOf(node)
        return mapOf(
            "nodeIndex" to index,
            "text" to node.text?.toString(),
            "contentDescription" to node.contentDescription?.toString(),
            "resourceId" to node.viewIdResourceName,
            "className" to node.className?.toString(),
            "packageName" to node.packageName?.toString(),
            "bounds" to mapOf(
                "left" to bounds.left,
                "top" to bounds.top,
                "right" to bounds.right,
                "bottom" to bounds.bottom,
            ),
            "centerX" to ((bounds.left + bounds.right) / 2.0),
            "centerY" to ((bounds.top + bounds.bottom) / 2.0),
            "isClickable" to node.isClickable,
            "isEnabled" to node.isEnabled,
            "isPassword" to node.isPassword,
            "isChecked" to node.isChecked,
            "isEditable" to node.isEditable,
            "isScrollable" to node.isScrollable,
        )
    }

    private fun boundsOf(node: AccessibilityNodeInfo): Rect {
        val rect = Rect()
        node.getBoundsInScreen(rect)
        return rect
    }
}
