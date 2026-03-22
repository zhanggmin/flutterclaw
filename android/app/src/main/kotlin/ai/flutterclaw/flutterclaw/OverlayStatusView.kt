package ai.flutterclaw.flutterclaw

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.InputType
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

class OverlayStatusView private constructor(private val context: Context) {

    companion object {
        private const val TAG = "OverlayStatusView"
        private const val SAFETY_TIMEOUT_MS = 30_000L
        private const val DONE_TIMEOUT_MS = 3_500L
        private const val MESSAGE_TIMEOUT_MS = 60_000L
        private const val DOT_ANIM_MS = 400L
        private const val MAX_HISTORY = 4
        // Alpha per row index (0=newest): full → fading
        private val ROW_ALPHA = floatArrayOf(1.0f, 0.55f, 0.30f, 0.15f)

        @Volatile private var instance: OverlayStatusView? = null

        fun getInstance(context: Context): OverlayStatusView {
            return instance ?: synchronized(this) {
                instance ?: OverlayStatusView(context.applicationContext).also { instance = it }
            }
        }
    }

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val handler = Handler(Looper.getMainLooper())

    // ─── Agent identity ──────────────────────────────────────────────────────────
    private var agentEmoji: String = "\uD83E\uDD16" // 🤖
    private var agentName: String = "Agent"

    // ─── Status stack (Mode A) ───────────────────────────────────────────────────
    private var statusView: LinearLayout? = null   // vertical container for history rows
    private var hideRunnable: Runnable? = null

    // History stack: newest first, max MAX_HISTORY entries
    private data class StatusEntry(val text: String, val isDone: Boolean, val ts: Long)
    private val statusHistory = mutableListOf<StatusEntry>()

    // Animated dots on the newest (non-done) row
    private var dotsLabel: TextView? = null
    private var dotAnimRunnable: Runnable? = null
    private var dotPhase = 0

    // ─── Message card (Mode B) ───────────────────────────────────────────────────
    private var messageView: LinearLayout? = null
    private var messageTimeoutRunnable: Runnable? = null
    private var currentRequestId: String? = null
    private var responseChannel: MethodChannel? = null

    // ─── Capture state ───────────────────────────────────────────────────────────
    private var captureRestoreRunnable: Runnable? = null
    private var hiddenForCapture = false

    // ─── Public API ──────────────────────────────────────────────────────────────

    fun canShow(): Boolean {
        val can = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(context)
        if (!can) Log.w(TAG, "canShow=false")
        return can
    }

    fun setAgent(name: String, emoji: String) {
        agentName = name
        agentEmoji = emoji
        // Rebuild the stack so emoji updates on all rows
        handler.post {
            if (statusView != null && statusHistory.isNotEmpty()) rebuildStack()
        }
    }

    fun setResponseChannel(channel: MethodChannel) {
        responseChannel = channel
    }

    // ─── Mode A: Status pill ─────────────────────────────────────────────────────

    fun show(text: String) {
        Log.d(TAG, "show('$text')")
        handler.post { showStatusInternal(text) }
    }

    fun hide() {
        handler.post { removeStatus() }
    }

    fun showDone(text: String) {
        Log.d(TAG, "showDone('$text')")
        handler.post { showDoneInternal(text) }
    }

    // ─── Mode B: Message card ────────────────────────────────────────────────────

    fun showMessage(
        text: String,
        buttons: List<Map<String, String>>?,
        inputType: String,
        requestId: String,
    ) {
        Log.d(TAG, "showMessage('$text', inputType=$inputType, requestId=$requestId)")
        handler.post { showMessageInternal(text, buttons, inputType, requestId) }
    }

    fun hideMessage() {
        handler.post { removeMessage("dismissed") }
    }

    // ─── Capture hide/restore ────────────────────────────────────────────────────

    fun hideForCapture() {
        handler.post {
            hiddenForCapture = true
            // Pause the status timer so it doesn't remove the overlay mid-capture
            cancelStatusTimer()
            statusView?.visibility = View.INVISIBLE
            messageView?.visibility = View.INVISIBLE
            captureRestoreRunnable?.let { handler.removeCallbacks(it) }
            captureRestoreRunnable = Runnable {
                Log.w(TAG, "hideForCapture safety timeout — force-restoring")
                hiddenForCapture = false
                statusView?.visibility = View.VISIBLE
                messageView?.visibility = View.VISIBLE
                captureRestoreRunnable = null
                // Re-arm the status timer now that capture is over
                if (statusView != null) armStatusTimer(SAFETY_TIMEOUT_MS)
            }
            handler.postDelayed(captureRestoreRunnable!!, 3_000L)
        }
    }

    fun showAfterCapture() {
        handler.post {
            Log.d(TAG, "showAfterCapture: sv=${statusView != null} hist=${statusHistory.size} hidden=$hiddenForCapture")
            captureRestoreRunnable?.let { handler.removeCallbacks(it) }
            captureRestoreRunnable = null
            hiddenForCapture = false
            messageView?.visibility = View.VISIBLE
            if (statusView != null) {
                statusView!!.visibility = View.VISIBLE
                armStatusTimer(SAFETY_TIMEOUT_MS)
            } else if (statusHistory.isNotEmpty()) {
                // statusView was lost during capture — rebuild from history
                Log.w(TAG, "showAfterCapture: statusView null but history exists, rebuilding")
                rebuildStack()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Internal — Mode A: Status pill
    // ═════════════════════════════════════════════════════════════════════════════

    private fun showStatusInternal(text: String) {
        Log.d(TAG, "showStatusInternal('$text') canShow=${canShow()} hidden=$hiddenForCapture sv=${statusView != null} hist=${statusHistory.size}")
        if (!canShow()) return
        pushHistory(StatusEntry(text, isDone = false, ts = System.currentTimeMillis()))
        rebuildStack()
    }

    private fun showDoneInternal(text: String) {
        Log.d(TAG, "showDoneInternal('$text') canShow=${canShow()} hidden=$hiddenForCapture sv=${statusView != null} hist=${statusHistory.size}")
        if (!canShow()) return
        pushHistory(StatusEntry(text, isDone = true, ts = System.currentTimeMillis()))
        rebuildStack()
    }

    private fun pushHistory(entry: StatusEntry) {
        // Avoid duplicate consecutive messages
        if (statusHistory.isNotEmpty() && statusHistory[0].text == entry.text) return
        statusHistory.add(0, entry)
        while (statusHistory.size > MAX_HISTORY) statusHistory.removeAt(statusHistory.size - 1)
    }

    /** Rebuild the vertical status stack from [statusHistory]. */
    private fun rebuildStack() {
        cancelStatusTimer()
        stopDotAnimation()

        if (statusHistory.isEmpty()) {
            Log.w(TAG, "rebuildStack: history empty, nothing to show")
            return
        }

        val dp = dpHelper()
        val existingAttached = statusView?.let {
            try { it.isAttachedToWindow } catch (_: Exception) { false }
        } ?: false
        Log.d(TAG, "rebuildStack: hist=${statusHistory.size} sv=${statusView != null} attached=$existingAttached hidden=$hiddenForCapture")

        // Create or reuse the vertical container (never clear history here)
        val container = statusView?.takeIf { existingAttached } ?: run {
            // Detach old view if any, but preserve history
            statusView?.let { old ->
                Log.d(TAG, "rebuildStack: removing stale container")
                try { windowManager.removeView(old) } catch (_: Exception) {}
            }
            statusView = null
            dotsLabel = null
            val c = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
            }
            if (!attachOverlay(c, touchable = false)) {
                Log.e(TAG, "rebuildStack: attachOverlay FAILED — overlay won't show")
                return
            }
            Log.d(TAG, "rebuildStack: new container attached")
            statusView = c
            c
        }

        container.removeAllViews()
        // Don't make visible while hidden for screenshot capture
        if (!hiddenForCapture) container.visibility = View.VISIBLE
        dotsLabel = null

        // Render rows: oldest at top, newest at bottom
        for (i in (statusHistory.size - 1) downTo 0) {
            val entry = statusHistory[i]
            val rowAlpha = ROW_ALPHA.getOrElse(i) { 0.10f }

            val pill = buildPill(dp)
            pill.alpha = rowAlpha

            if (entry.isDone) {
                // Done row: green checkmark
                pill.addView(TextView(context).apply {
                    this.text = "\u2713"
                    setTextColor(0xFF4CAF50.toInt())
                    textSize = 14f
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginEnd = dp(6f) }
                })
            } else {
                // Normal row: agent emoji
                pill.addView(TextView(context).apply {
                    this.text = agentEmoji
                    textSize = 14f
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginEnd = dp(6f) }
                })
            }

            pill.addView(buildLabel(entry.text, dp))

            // Animated dots only on the newest non-done row
            if (i == 0 && !entry.isDone) {
                val dots = TextView(context).apply {
                    this.text = ""
                    setTextColor(0xFFE0E0E0.toInt())
                    textSize = 13f
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    )
                }
                dotsLabel = dots
                pill.addView(dots)
            }

            // Small gap between rows
            pill.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { if (i > 0) bottomMargin = dp(3f) }

            container.addView(pill)
        }

        // Arm timers
        val newestIsDone = statusHistory.firstOrNull()?.isDone == true
        armStatusTimer(if (newestIsDone) DONE_TIMEOUT_MS else SAFETY_TIMEOUT_MS)
        if (!newestIsDone) startDotAnimation()
    }

    // ─── Dot animation ───────────────────────────────────────────────────────────

    private fun startDotAnimation() {
        stopDotAnimation()
        dotPhase = 0
        dotAnimRunnable = object : Runnable {
            override fun run() {
                dotPhase = (dotPhase + 1) % 4
                dotsLabel?.text = ".".repeat(dotPhase)
                handler.postDelayed(this, DOT_ANIM_MS)
            }
        }
        handler.postDelayed(dotAnimRunnable!!, DOT_ANIM_MS)
    }

    private fun stopDotAnimation() {
        dotAnimRunnable?.let { handler.removeCallbacks(it) }
        dotAnimRunnable = null
        dotsLabel?.text = ""
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Internal — Mode B: Message card
    // ═════════════════════════════════════════════════════════════════════════════

    private fun showMessageInternal(
        text: String,
        buttons: List<Map<String, String>>?,
        inputType: String,
        requestId: String,
    ) {
        if (!canShow()) return

        // Dismiss any previous message
        removeMessageSilent("dismissed")

        // Hide the status pill while message is showing
        statusView?.visibility = View.INVISIBLE

        currentRequestId = requestId
        val dp = dpHelper()
        val isTextInput = inputType == "text"

        // ── Card container ───────────────────────────────────────────────────
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16f), dp(12f), dp(16f), dp(14f))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(0xEE1A1A2E.toInt())
                cornerRadius = dp(16f).toFloat()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }

        // ── Header: emoji + name + dismiss "✕" ──────────────────────────────
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(8f) }
        }

        header.addView(TextView(context).apply {
            this.text = agentEmoji
            textSize = 18f
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginEnd = dp(6f) }
        })

        header.addView(TextView(context).apply {
            this.text = agentName
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 15f
            setTypeface(null, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f,
            )
        })

        // Dismiss button
        header.addView(TextView(context).apply {
            this.text = "\u2715"
            setTextColor(0xAA888888.toInt())
            textSize = 16f
            setPadding(dp(8f), dp(4f), dp(4f), dp(4f))
            setOnClickListener { removeMessage("dismissed") }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        })

        card.addView(header)

        // ── Body: message text ───────────────────────────────────────────────
        card.addView(TextView(context).apply {
            this.text = text
            setTextColor(0xFFE0E0E0.toInt())
            textSize = 14f
            maxLines = 4
            ellipsize = android.text.TextUtils.TruncateAt.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { bottomMargin = dp(12f) }
        })

        // ── Footer: buttons or text input ────────────────────────────────────
        if (isTextInput) {
            val inputRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
            }

            val hint = buttons?.firstOrNull()?.get("label") ?: "Type here..."
            val editText = EditText(context).apply {
                setHint(hint)
                setHintTextColor(0x88AAAAAA.toInt())
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 14f
                setInputType(InputType.TYPE_CLASS_TEXT)
                setSingleLine(true)
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(0xFF2A2A3E.toInt())
                    cornerRadius = dp(10f).toFloat()
                }
                setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
                layoutParams = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f,
                ).apply { marginEnd = dp(8f) }
            }
            inputRow.addView(editText)

            // Send button
            val sendBtn = TextView(context).apply {
                this.text = "\u279C" // ➜
                setTextColor(0xFFBB86FC.toInt())
                textSize = 20f
                gravity = Gravity.CENTER
                setPadding(dp(10f), dp(6f), dp(10f), dp(6f))
                background = android.graphics.drawable.GradientDrawable().apply {
                    setColor(0xFF2A2A3E.toInt())
                    cornerRadius = dp(10f).toFloat()
                }
                setOnClickListener {
                    val response = editText.text.toString().trim()
                    if (response.isNotEmpty()) {
                        // Hide keyboard
                        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                        imm?.hideSoftInputFromWindow(editText.windowToken, 0)
                        removeMessage(response)
                    }
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
            }
            inputRow.addView(sendBtn)

            card.addView(inputRow)
        } else {
            // Buttons mode
            val buttonRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
            }

            buttons?.take(4)?.forEach { btn ->
                val label = btn["label"] ?: ""
                val value = btn["value"] ?: label
                buttonRow.addView(TextView(context).apply {
                    this.text = label
                    setTextColor(0xFFBB86FC.toInt())
                    textSize = 13f
                    setTypeface(null, Typeface.BOLD)
                    gravity = Gravity.CENTER
                    setPadding(dp(14f), dp(8f), dp(14f), dp(8f))
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(0xFF2A2A3E.toInt())
                        cornerRadius = dp(20f).toFloat()
                    }
                    setOnClickListener { removeMessage(value) }
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginEnd = dp(6f) }
                })
            }

            card.addView(buttonRow)
        }

        // ── Attach as touchable overlay ──────────────────────────────────────
        val focusable = isTextInput // text input needs keyboard focus
        if (attachMessageOverlay(card, focusable = focusable)) {
            messageView = card
            armMessageTimeout()
        }
    }

    private fun removeMessage(responseValue: String) {
        handler.post {
            removeMessageSilent(responseValue)
            // Restore status pill
            statusView?.visibility = View.VISIBLE
        }
    }

    private fun removeMessageSilent(responseValue: String) {
        cancelMessageTimeout()
        val reqId = currentRequestId
        currentRequestId = null
        val view = messageView ?: return
        messageView = null

        // Hide keyboard if showing
        val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        imm?.hideSoftInputFromWindow(view.windowToken, 0)

        try {
            windowManager.removeView(view)
        } catch (_: Exception) {}

        // Send response back to Dart
        if (reqId != null) {
            try {
                responseChannel?.invokeMethod("overlay_user_response", mapOf(
                    "requestId" to reqId,
                    "value" to responseValue,
                ))
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send overlay response: $e")
            }
        }
    }

    private fun armMessageTimeout() {
        cancelMessageTimeout()
        messageTimeoutRunnable = Runnable { removeMessage("timeout") }
        handler.postDelayed(messageTimeoutRunnable!!, MESSAGE_TIMEOUT_MS)
    }

    private fun cancelMessageTimeout() {
        messageTimeoutRunnable?.let { handler.removeCallbacks(it) }
        messageTimeoutRunnable = null
    }

    // ═════════════════════════════════════════════════════════════════════════════
    // Shared helpers
    // ═════════════════════════════════════════════════════════════════════════════

    private fun dpHelper(): (Float) -> Int = { value: Float ->
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, context.resources.displayMetrics).toInt()
    }

    private fun buildPill(dp: (Float) -> Int): LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12f), dp(6f), dp(16f), dp(6f))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(0xDD1A1A2E.toInt())
                cornerRadius = dp(20f).toFloat()
            }
        }

    private fun buildLabel(text: String, dp: (Float) -> Int): TextView =
        TextView(context).apply {
            this.text = text
            setTextColor(0xFFE0E0E0.toInt())
            textSize = 13f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

    /** Attach the status pill (non-touchable). */
    private fun attachOverlay(view: LinearLayout, touchable: Boolean): Boolean {
        if (!canShow()) {
            Log.w(TAG, "attachOverlay: canShow=false, aborting")
            return false
        }
        val dp = dpHelper()
        var flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        if (!touchable) {
            flags = flags or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(48f)
        }

        return try {
            windowManager.addView(view, params)
            Log.d(TAG, "attachOverlay: success (touchable=$touchable)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "attachOverlay: FAILED — ${e.javaClass.simpleName}: ${e.message}", e)
            false
        }
    }

    /** Attach the message card (touchable, optionally focusable for keyboard). */
    private fun attachMessageOverlay(view: LinearLayout, focusable: Boolean): Boolean {
        val dp = dpHelper()
        val screenWidth = context.resources.displayMetrics.widthPixels
        val maxWidth = (screenWidth * 0.85).toInt()

        var flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        if (!focusable) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        }

        val params = WindowManager.LayoutParams(
            maxWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(48f)
        }

        return try {
            windowManager.addView(view, params)
            Log.d(TAG, "attachMessageOverlay: success (focusable=$focusable)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "attachMessageOverlay: failed", e)
            false
        }
    }

    // ─── Status pill lifecycle ───────────────────────────────────────────────────

    private fun cancelStatusTimer() {
        hideRunnable?.let { handler.removeCallbacks(it) }
        hideRunnable = null
    }

    private fun armStatusTimer(ms: Long) {
        cancelStatusTimer()
        hideRunnable = Runnable { removeStatus() }
        handler.postDelayed(hideRunnable!!, ms)
    }

    private fun removeStatus() {
        if (hiddenForCapture) {
            Log.d(TAG, "removeStatus: skipped — hidden for capture")
            return
        }
        Log.d(TAG, "removeStatus (timer/explicit hide)")
        cancelStatusTimer()
        stopDotAnimation()
        removeStatusSilent()
    }

    private fun removeStatusSilent() {
        val view = statusView ?: return
        Log.d(TAG, "removeStatusSilent: removing view, clearing ${statusHistory.size} history entries")
        statusView = null
        dotsLabel = null
        statusHistory.clear()
        try {
            windowManager.removeView(view)
        } catch (_: Exception) {}
    }
}
