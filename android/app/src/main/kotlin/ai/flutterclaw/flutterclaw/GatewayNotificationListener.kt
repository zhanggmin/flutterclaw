package ai.flutterclaw.flutterclaw

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import com.pravera.flutter_foreground_task.PreferencesKey as PrefsKey
import com.pravera.flutter_foreground_task.models.ForegroundServiceAction
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus
import com.pravera.flutter_foreground_task.models.NotificationContent
import com.pravera.flutter_foreground_task.service.ForegroundService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Listener for the foreground task's Flutter engine. Registers a method channel
 * so the task (running in a separate engine) can request notification updates.
 * On Android 15, updateService() from the task's engine does not apply; updating
 * via SharedPreferences + API_UPDATE from the service process works.
 */
class GatewayNotificationListener(private val context: Context) : FlutterForegroundTaskLifecycleListener {

    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        if (flutterEngine == null) return
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai.flutterclaw/notification_update"
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method == "update") {
                @Suppress("UNCHECKED_CAST")
                val args = call.arguments as? Map<String, Any?>
                val title = args?.get("notificationContentTitle") as? String ?: ""
                val text = args?.get("notificationContentText") as? String ?: ""
                val map = mapOf(
                    PrefsKey.NOTIFICATION_CONTENT_TITLE to title,
                    PrefsKey.NOTIFICATION_CONTENT_TEXT to text,
                )
                NotificationContent.updateData(context.applicationContext, map)
                ForegroundServiceStatus.setData(context.applicationContext, ForegroundServiceAction.API_UPDATE)
                val intent = Intent(context.applicationContext, ForegroundService::class.java)
                ContextCompat.startForegroundService(context.applicationContext, intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        // Register the overlay channel on the background engine so that
        // Dart code running in the foreground-task isolate can show/hide
        // the overlay using the same OverlayStatusView singleton.
        val overlayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ai.flutterclaw/overlay")
        val overlay = OverlayStatusView.getInstance(context)
        overlay.setResponseChannel(overlayChannel)
        overlayChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "overlay_check_permission" -> result.success(overlay.canShow())
                    "overlay_set_agent" -> {
                        val name = call.argument<String>("name") ?: "Agent"
                        val emoji = call.argument<String>("emoji") ?: "\uD83E\uDD16"
                        overlay.setAgent(name, emoji)
                        result.success(true)
                    }
                    "overlay_show" -> {
                        val text = call.argument<String>("text") ?: ""
                        overlay.show(text)
                        result.success(true)
                    }
                    "overlay_hide" -> {
                        overlay.hide()
                        result.success(true)
                    }
                    "overlay_show_done" -> {
                        val text = call.argument<String>("text") ?: "Done"
                        overlay.showDone(text)
                        result.success(true)
                    }
                    "overlay_show_message" -> {
                        val text = call.argument<String>("text") ?: ""
                        val inputType = call.argument<String>("inputType") ?: "buttons"
                        val requestId = call.argument<String>("requestId") ?: ""
                        @Suppress("UNCHECKED_CAST")
                        val buttons = (call.argument<List<Map<String, String>>>("buttons"))
                        overlay.showMessage(text, buttons, inputType, requestId)
                        result.success(true)
                    }
                    "overlay_hide_message" -> {
                        overlay.hideMessage()
                        result.success(true)
                    }
                    "overlay_touch_tap" -> {
                        val x = (call.argument<Number>("x") ?: 0).toFloat()
                        val y = (call.argument<Number>("y") ?: 0).toFloat()
                        TouchFeedbackOverlay.getInstance(context).showTap(x, y)
                        result.success(true)
                    }
                    "overlay_touch_swipe" -> {
                        val x1 = (call.argument<Number>("x1") ?: 0).toFloat()
                        val y1 = (call.argument<Number>("y1") ?: 0).toFloat()
                        val x2 = (call.argument<Number>("x2") ?: 0).toFloat()
                        val y2 = (call.argument<Number>("y2") ?: 0).toFloat()
                        TouchFeedbackOverlay.getInstance(context).showSwipe(x1, y1, x2, y2)
                        result.success(true)
                    }
                    "overlay_touch_type" -> {
                        val text = call.argument<String>("text") ?: ""
                        TouchFeedbackOverlay.getInstance(context).showType(text)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}
    override fun onTaskRepeatEvent() {}
    override fun onTaskDestroy() {}
    override fun onEngineWillDestroy() {}
}
