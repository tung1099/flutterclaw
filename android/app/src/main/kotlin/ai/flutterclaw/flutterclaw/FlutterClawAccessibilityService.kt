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
        var rootList: List<AccessibilityNodeInfo> = emptyList()

        // ─── Get root windows ─────────────────────────────
        val windows = this.windows
        if (windows != null && windows.isNotEmpty()) {
            val systemPackages = listOf(
                "com.samsung.android.app.cocktailbarservice",
                "com.samsung.android.systemui",
                "com.android.systemui",
                "com.android.launcher"
            )
            rootList = windows
                .mapNotNull { it.root }
                .filter { root ->
                    val pkg = root.packageName?.toString() ?: ""
                    !systemPackages.any { pkg.startsWith(it) }
                }
        }

        if (rootList.isEmpty()) {
            val activeRoot = this.rootInActiveWindow
            if (activeRoot != null) {
                rootList = listOf(activeRoot)
            }
        }

        if (rootList.isEmpty()) {
            return mapOf("success" to false, "message" to "No active window found")
        }

        val queryLower = query.lowercase()
        val isSearchQuery = queryLower.contains("tìm") ||
                queryLower.contains("search") ||
                queryLower.contains("tim")

        // ─── Helper: find search bar ──────────────────────
        fun findSearchBar(nodes: List<AccessibilityNodeInfo>): AccessibilityNodeInfo? {
            val topNodes = nodes.filter { node ->
                val bounds = android.graphics.Rect()
                node.getBoundsInScreen(bounds)
                bounds.top in 0..500
            }

            // Ưu tiên icon search
            val searchIcon = topNodes.firstOrNull { node ->
                val resId = (node.viewIdResourceName ?: "").lowercase()
                val desc = (node.contentDescription?.toString() ?: "").lowercase()
                val text = (node.text?.toString() ?: "").lowercase()

                (resId.contains("search") || desc.contains("search") || text.contains("search") ||
                        resId.contains("tìm") || desc.contains("tìm")) &&
                        node.isClickable && node.isEnabled
            }
            if (searchIcon != null) return searchIcon

            // EditText (bao gồm cả TextInputEditText, AppCompatEditText)
            val editText = topNodes.firstOrNull {
                val className = it.className?.toString() ?: ""
                (className.contains("EditText", ignoreCase = true) ||
                        className.contains("TextInputEditText", ignoreCase = true) ||
                        className.contains("AppCompatEditText", ignoreCase = true)) && it.isEnabled
            }
            if (editText != null) return editText

            // Tìm view có inputType (text search)
            val textInput = topNodes.firstOrNull {
                it.isEditable && it.isEnabled
            }
            if (textInput != null) return textInput

            // Tìm button/clickable đầu tiên ở top (thường là search icon hoặc search bar container)
            return topNodes.firstOrNull { it.isClickable && it.isEnabled }
        }

        // ─── Helper: tap search bar position (fallback for custom views) ──────
        fun tapSearchBarPosition(screenWidth: Int, screenHeight: Int): Boolean {
            // Search bar Shopee thường ở vị trí center-top, ~100-200px từ top
            val x = screenWidth / 2f
            val y = screenHeight * 0.08f // ~8% từ top

            android.util.Log.d("FlutterClaw", "tapSearchBarPosition: $x, $y")
            return dispatchTap(x, y)
        }

        // ─── MAIN LOOP ────────────────────────────────────
        for (root in rootList) {
            val allNodes = collectNodes(root, null, "all")

            android.util.Log.d(
                "FlutterClaw",
                "clickElement: ${allNodes.size} nodes, query='$query'"
            )

            var matchedNodes: List<AccessibilityNodeInfo> = emptyList()

            // ─── Match logic ───────────────────────────────
            matchedNodes = when {
                by == "id" || by == "text" -> {
                    allNodes.filter {
                        it.viewIdResourceName?.contains(query, true) == true
                    }.ifEmpty {
                        allNodes.filter {
                            it.text?.toString()?.contains(query, true) == true ||
                                    it.contentDescription?.toString()?.contains(query, true) == true
                        }
                    }
                }

                by == "class" -> {
                    allNodes.filter {
                        it.className?.contains(query, true) == true
                    }
                }

                else -> {
                    collectNodes(root, query, by)
                }
            }

            // ─── Nếu search → tìm search bar ───────────────
            val finalCandidates =
                if (matchedNodes.isEmpty() && isSearchQuery) {
                    findSearchBar(allNodes)?.let { listOf(it) } ?: emptyList()
                } else matchedNodes

            // 🔥 FORCE TAP CHO SEARCH (fix Shopee)
            if (isSearchQuery) {
                android.util.Log.d("FlutterClaw", "Force tap search area")

                val rootBounds = android.graphics.Rect()
                root.getBoundsInScreen(rootBounds)

                val x = rootBounds.centerX().toFloat()
                val y = 180f  // 👈 chỉnh nếu cần

                val ok = dispatchTap(x, y)

                return mapOf(
                    "success" to ok,
                    "method" to "force_search_tap",
                    "x" to x,
                    "y" to y
                )
            }

            var clickable = finalCandidates.firstOrNull {
                it.isClickable && it.isEnabled
            } ?: finalCandidates.firstOrNull { it.isEnabled }

            // ─── Fallback: tap theo vị trí cố định cho search ─────────────
            if (clickable == null && isSearchQuery) {
                android.util.Log.d("FlutterClaw", "Search query but no element found → fallback position")
                val dm = resources?.displayMetrics
                val screenWidth = dm?.widthPixels ?: 1440
                val screenHeight = dm?.heightPixels ?: 2960

                // Try tapping search bar position
                val posOk = tapSearchBarPosition(screenWidth, screenHeight)
                if (posOk) {
                    return mapOf(
                        "success" to true,
                        "method" to "fallback_search_position",
                        "x" to (screenWidth / 2f),
                        "y" to (screenHeight * 0.08f),
                        "note" to "Tapped at estimated search bar position"
                    )
                }
            }

            // ─── CLICK ─────────────────────────────────────
            if (clickable != null) {
                val serialized = serializeNode(clickable, 0)

                val bounds = android.graphics.Rect()
                clickable.getBoundsInScreen(bounds)

                val x = bounds.centerX().toFloat()
                val y = bounds.centerY().toFloat()

                android.util.Log.d(
                    "FlutterClaw",
                    "clickElement: clicking at $x,$y"
                )

                var ok = clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK)

                // 🔥 fallback gesture nếu ACTION_CLICK fail
                if (!ok) {
                    android.util.Log.d("FlutterClaw", "ACTION_CLICK failed → gesture tap")
                    ok = dispatchTap(x, y)
                }

                clickable.recycle()

                return mapOf(
                    "success" to ok,
                    "method" to if (ok) "element" else "gesture",
                    "x" to x,
                    "y" to y,
                    "element" to serialized
                )
            }
        }

        // ─── FINAL FALLBACK (QUAN TRỌNG) ──────────────────
        android.util.Log.d("FlutterClaw", "Fallback: tap top center")

        val rootBounds = android.graphics.Rect()
        rootList.first().getBoundsInScreen(rootBounds)

        val x = rootBounds.centerX().toFloat()
        val y = 150f

        val ok = dispatchTap(x, y)

        return mapOf(
            "success" to ok,
            "method" to "fallback_top_area",
            "x" to x,
            "y" to y
        )
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
