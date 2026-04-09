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
        val root = getActiveRoot() ?: return mapOf("success" to false, "message" to "No active window")
        val allNodes = collectNodes(root, null, "all")

        val isSearchQuery = query.contains("tìm", ignoreCase = true) || 
                            query.contains("search", ignoreCase = true) || 
                            query.contains("tim", ignoreCase = true)

        android.util.Log.d("FlutterClaw", "clickElement: ${allNodes.size} nodes, query='$query', by='$by', isSearch=$isSearchQuery")

        // B1: Exact match theo by
        var matchedNodes = when (by) {
            "id" -> allNodes.filter { it.viewIdResourceName?.contains(query, true) == true }
            "text" -> allNodes.filter {
                it.text?.contains(query, true) == true || it.contentDescription?.contains(query, true) == true
            }
            "description" -> allNodes.filter { it.contentDescription?.contains(query, true) == true }
            "class" -> allNodes.filter { it.className?.contains(query, true) == true }
            else -> allNodes.filter {
                it.text?.contains(query, true) == true ||
                it.contentDescription?.contains(query, true) == true ||
                it.viewIdResourceName?.contains(query, true) == true
            }
        }

        // B2: Nếu là search query → tìm search bar/icon
        var target: AccessibilityNodeInfo? = null
        if (matchedNodes.isEmpty() || isSearchQuery) {
            target = findSearchTarget(allNodes, isSearchQuery)
            if (target != null) {
                android.util.Log.d("FlutterClaw", "Found search target: ${target.text ?: target.contentDescription}")
            }
        }

        // B3: Dùng exact match nếu có
        if (target == null && matchedNodes.isNotEmpty()) {
            target = matchedNodes.firstOrNull { it.isClickable && it.isEnabled }
                ?: matchedNodes.firstOrNull { it.isEnabled }
        }

        // B4: Execute click
        val bounds = android.graphics.Rect()
        return if (target != null) {
            target.getBoundsInScreen(bounds)
            val x = bounds.centerX().toFloat()
            val y = bounds.centerY().toFloat()
            android.util.Log.d("FlutterClaw", "Clicking target: ${target.text ?: target.contentDescription} at $x,$y")

            var ok = target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            if (!ok) {
                ok = dispatchTap(x, y)
            }

            mapOf("success" to ok, "method" to "element", "x" to x, "y" to y,
                "elementText" to (target.text ?: target.contentDescription ?: ""))
        } else {
            // KHÔNG fallback lung tung - báo lỗi rõ ràng
            android.util.Log.d("FlutterClaw", "No element found for query: $query")
            mapOf("success" to false, "message" to "Element '$query' not found on screen")
        }
    }

    private fun findSearchTarget(nodes: List<AccessibilityNodeInfo>, isSearchQuery: Boolean): AccessibilityNodeInfo? {
        if (!isSearchQuery) return null

        // Tìm trên toàn màn hình thay vì chỉ top 600px - vì search bar có thể ở vị trí khác
        // Ưu tiên tìm EditText editable
        val editText = nodes.firstOrNull { node ->
            val className = node.className?.toString() ?: ""
            (className.contains("EditText", ignoreCase = true) ||
                    className.contains("TextInput", ignoreCase = true)) && node.isEnabled
        }
        if (editText != null) {
            android.util.Log.d("FlutterClaw", "Found EditText: ${editText.text}")
            return editText
        }

        // Tìm text input editable
        val editable = nodes.firstOrNull { it.isEditable && it.isEnabled }
        if (editable != null) {
            android.util.Log.d("FlutterClaw", "Found editable field")
            return editable
        }

        // Tìm icon/biểu tượng search trên toàn màn hình
        val searchIcon = nodes.firstOrNull { node ->
            val resId = node.viewIdResourceName ?: ""
            val desc = node.contentDescription ?: ""
            val text = node.text ?: ""
            val className = node.className?.toString() ?: ""
            
            // Dùng ignoreCase trong contains
            ((desc.contains("search", ignoreCase = true) || text.contains("search", ignoreCase = true) || 
              text.contains("tìm", ignoreCase = true) || text.contains("tìm kiếm", ignoreCase = true)) && node.isClickable && node.isEnabled) ||
            (className.contains("ImageView") && (desc.isNotEmpty() || text.isNotEmpty()) && 
             (desc.contains("search", ignoreCase = true) || text.contains("search", ignoreCase = true) || resId.contains("search", ignoreCase = true)))
        }
        if (searchIcon != null) {
            android.util.Log.d("FlutterClaw", "Found search icon: ${searchIcon.contentDescription ?: searchIcon.text}")
            return searchIcon
        }

        // Tìm TextView có text "Tìm kiếm" hoặc tương tự
        val searchText = nodes.firstOrNull { node ->
            val text = node.text ?: ""
            val desc = node.contentDescription ?: ""
            (text.contains("tìm", ignoreCase = true) || text.contains("search", ignoreCase = true) || 
             desc.contains("tìm", ignoreCase = true) || desc.contains("search", ignoreCase = true)) && node.isClickable
        }
        if (searchText != null) return searchText

        // Fallback: tìm container có thể click được gần top màn hình (0-500px)
        val topClickable = nodes.filter { node ->
            val bounds = android.graphics.Rect()
            node.getBoundsInScreen(bounds)
            bounds.top in 0..500 && node.isClickable && node.isEnabled
        }.firstOrNull()
        
        if (topClickable != null) {
            android.util.Log.d("FlutterClaw", "Fallback: clicking top element: ${topClickable.contentDescription ?: topClickable.text}")
            return topClickable
        }

        android.util.Log.d("FlutterClaw", "No search bar or search icon found on screen")
        return null
    }

    private fun getActiveRoot(): AccessibilityNodeInfo? {
        val windows = this.windows
        if (windows != null && windows.isNotEmpty()) {
            val systemPackages = setOf(
                "com.samsung.android.app.cocktailbarservice",
                "com.samsung.android.systemui",
                "com.android.systemui",
                "com.android.launcher"
            )
            return windows
                .mapNotNull { it.root }
                .firstOrNull { root ->
                    val pkg = root.packageName?.toString() ?: ""
                    !systemPackages.any { pkg.startsWith(it) }
                }
        }
        return this.rootInActiveWindow
    }

    // ─── Global actions ──────────────────────────────────────────────────────

    fun doGlobalAction(action: String): Boolean {
        return when (action) {
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            "quick_settings" -> performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
            "enter" -> {
                // Simulate pressing Enter/Go button - tap near bottom where keyboard's search button appears
                val dm = resources.displayMetrics
                val cx = dm.widthPixels / 2f
                val cy = dm.heightPixels * 0.85f // Near bottom - keyboard action button area
                android.util.Log.d("FlutterClaw", "doGlobalAction enter: tapping at ($cx, $cy)")
                return dispatchTap(cx, cy)
            }
            else -> false
        }
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

    private fun dispatchTap(x: Float, y: Float): Boolean {
        val path = android.graphics.Path()
        path.moveTo(x, y)

        val gesture = android.accessibilityservice.GestureDescription.Builder()
            .addStroke(
                android.accessibilityservice.GestureDescription.StrokeDescription(
                    path, 0, 100
                )
            )
            .build()

        return dispatchGesture(gesture, null, null)
    }
}
