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

        /** Scale bitmap so its longest side is at most [maxPx]. */
        fun scaleDown(bmp: android.graphics.Bitmap, maxPx: Int): android.graphics.Bitmap {
            val w = bmp.width
            val h = bmp.height
            if (w <= maxPx && h <= maxPx) return bmp
            val ratio = maxPx.toFloat() / maxOf(w, h)
            return android.graphics.Bitmap.createScaledBitmap(
                bmp, (w * ratio).toInt(), (h * ratio).toInt(), true
            )
        }
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
        // Get root windows - try multiple approaches
        var rootList: List<AccessibilityNodeInfo> = emptyList()
        
        // Try windows first
        val windows = this.windows
        if (windows != null && windows.isNotEmpty()) {
            rootList = windows.mapNotNull { it.root }.filter { it != null }
        }
        
        // Fallback to rootInActiveWindow
        if (rootList.isEmpty()) {
            val activeRoot = this.rootInActiveWindow
            if (activeRoot != null) {
                rootList = listOf(activeRoot)
            }
        }

        if (rootList.isEmpty()) {
            return mapOf("success" to false, "message" to "No active window found")
        }

        val textSearch = by == "text"
        val queryLower = query.lowercase()
        val isSearchQuery = queryLower.contains("tìm") || 
                           queryLower.contains("search") ||
                           queryLower.contains("tim") ||
                           queryLower.contains("search icon") ||
                           queryLower.contains("search box")

        // Common search button/input patterns - expanded list
        val searchPatterns = listOf(
            "tìm", "search", "tim kiem", "search...", "tìm kiếm",
            "search products", "nhập từ khóa", "tìm sản phẩm",
            "nhập", "tìm kiếm sản phẩm", "search product"
        )

        // Helper to find any clickable/searchable element at top of screen
        fun findTopScreenElement(nodes: List<AccessibilityNodeInfo>): AccessibilityNodeInfo? {
            // Look for elements in top 25% of screen (search bars are usually at top)
            val topNodes = nodes.filter { node ->
                val bounds = android.graphics.Rect()
                node.getBoundsInScreen(bounds)
                bounds.top < 400 // Top 400 pixels
            }
            // Prefer EditText at top (usually the search input)
            return topNodes.firstOrNull { 
                it.className?.contains("EditText") == true && it.isFocusable && it.isEnabled 
            } ?: topNodes.firstOrNull { 
                it.isClickable && it.isEnabled 
            } ?: topNodes.firstOrNull { it.isEnabled }
        }

        for (root in rootList) {
            val allNodes = collectNodes(root, null, "all")
            
            // Debug: log what nodes we found
            android.util.Log.d("FlutterClaw", "clickElement: found ${allNodes.size} nodes for query '$query'")
            
            val matchedNodes = if (textSearch) {
                // First: exact text match
                val exact = allNodes.filter { node ->
                    node.text?.toString()?.contains(query, ignoreCase = true) == true ||
                    node.contentDescription?.toString()?.contains(query, ignoreCase = true) == true
                }
                if (exact.isNotEmpty()) exact else
                
                // Second: partial match (starts with query)
                allNodes.filter { node ->
                    val text = node.text?.toString() ?: ""
                    val desc = node.contentDescription?.toString() ?: ""
                    val matchLen = minOf(query.length, maxOf(text.length, desc.length))
                    if (matchLen > 0) {
                        text.substring(0, minOf(text.length, matchLen)).equals(
                            query.substring(0, minOf(query.length, matchLen)), ignoreCase = true) ||
                        desc.substring(0, minOf(desc.length, matchLen)).equals(
                            query.substring(0, minOf(query.length, matchLen)), ignoreCase = true)
                    } else false
                }.ifEmpty {
                    // Third: for search queries, find by common patterns
                    if (isSearchQuery) {
                        allNodes.filter { node ->
                            val text = node.text?.toString()?.lowercase() ?: ""
                            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                            searchPatterns.any { pattern -> 
                                text.contains(pattern) || desc.contains(pattern) 
                            }
                        }
                    } else emptyList()
                }
            } else {
                collectNodes(root, query, by)
            }

            // If still no match but this is a search query, try top screen elements
            val finalCandidates = if (matchedNodes.isEmpty() && isSearchQuery) {
                val top = findTopScreenElement(allNodes)
                if (top != null) listOf(top) else emptyList()
            } else matchedNodes

            // Select best candidate
            val clickable = when {
                isSearchQuery -> {
                    finalCandidates.firstOrNull { 
                        it.className?.contains("EditText") == true && it.isFocusable 
                    } ?: finalCandidates.firstOrNull { it.isClickable && it.isEnabled }
                        ?: finalCandidates.firstOrNull { it.isEnabled }
                }
                else -> {
                    finalCandidates.firstOrNull { it.isClickable && it.isEnabled }
                        ?: finalCandidates.firstOrNull { it.isEnabled }
                }
            }

            if (clickable != null) {
                val serialized = serializeNode(clickable, 0)
                val isEditText = clickable.className?.contains("EditText") == true
                val bounds = android.graphics.Rect()
                clickable.getBoundsInScreen(bounds)
                android.util.Log.d("FlutterClaw", "clickElement: clicking ${serialized["text"] ?: serialized["resourceId"]} at ${bounds.centerX()},${bounds.centerY()}")
                
                val ok = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                clickable.recycle()

                // After click, try to focus an EditText field
                val focusedRoot = this.rootInActiveWindow
                if (ok && focusedRoot != null) {
                    val editTexts = collectNodes(focusedRoot, null, "all")
                        .filter { it.className?.contains("EditText") == true && it.isFocusable }
                    
                    for (edit in editTexts) {
                        if (edit.isEnabled && edit.performAction(AccessibilityNodeInfo.ACTION_FOCUS)) {
                            edit.recycle()
                            return buildMap {
                                put("success", true)
                                put("element", serialized)
                                put("readyForInput", true)
                                put("message", "clicked and focused for input")
                            }
                        }
                        edit.recycle()
                    }
                }

                return buildMap {
                    put("success", ok)
                    put("element", serialized)
                    put("message", when {
                        ok -> "clicked"
                        else -> "ACTION_CLICK returned false"
                    })
                }
            }
        }
        
        // Last resort: try to find ANY EditText on screen
        for (root in rootList) {
            val allNodes = collectNodes(root, null, "all")
            val editText = allNodes.firstOrNull { 
                it.className?.contains("EditText") == true && it.isFocusable && it.isEnabled 
            }
            if (editText != null) {
                val serialized = serializeNode(editText, 0)
                val ok = editText.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                editText.recycle()
                if (ok) {
                    return buildMap {
                        put("success", true)
                        put("element", serialized)
                        put("readyForInput", true)
                        put("message", "auto-clicked first input field")
                        put("fallback", true)
                    }
                }
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
                        val softBmp = bmp.copy(android.graphics.Bitmap.Config.ARGB_8888, false)
                        bmp.recycle()
                        val scaled = scaleDown(softBmp, 1080)
                        if (scaled !== softBmp) softBmp.recycle()
                        val baos = ByteArrayOutputStream()
                        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 60, baos)
                        scaled.recycle()
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
