package com.example.mobile_pilot

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle

/** A system-rendered status surface, not a service that keeps inference alive. */
class AiTaskNotification(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private var startedAt = 0L
    private var active = false
    private var dismissed = false

    fun dismiss() { dismissed = true }

    fun publish(status: String, running: Boolean) {
        if (!running) {
            active = false
            manager.cancel(ID)
            return
        }
        if (!active) {
            startedAt = System.currentTimeMillis()
            dismissed = false
            active = true
        }
        if (dismissed || (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "สถานะงาน AI", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(context, 0,
            Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(name: String) = PendingIntent.getBroadcast(context, name.hashCode(),
            Intent(context, AiTaskNotificationReceiver::class.java).setAction(name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_ai_task)
            .setContentTitle("MobilePilot กำลังทำงาน")
            .setContentText(status.take(240))
            .setStyle(Notification.BigTextStyle().bigText(status.take(240)))
            .setContentIntent(open)
            .setDeleteIntent(action(DISMISS))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(startedAt)
            .setUsesChronometer(true)
            .addAction(Notification.Action.Builder(null, "หยุดงาน", action(STOP)).build())
        if (Build.VERSION.SDK_INT >= 36) {
            // Public EXTRA_REQUEST_PROMOTED_ONGOING (36.1). Using its documented
            // wire key lets this project compile with SDK 36.0; older OSes may ignore it.
            builder.addExtras(Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
        }
        try { manager.notify(ID, builder.build()) } catch (_: SecurityException) {
            // Permission can be revoked between checking and posting.
        }
    }

    companion object {
        const val ID = 401
        const val CHANNEL = "ai_task_status"
        const val STOP = "com.example.mobile_pilot.STOP_AI_TASK"
        const val DISMISS = "com.example.mobile_pilot.DISMISS_AI_TASK"
    }
}

class AiTaskNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            AiTaskNotification.STOP -> AiTaskOverlayBridge.requestStop()
            AiTaskNotification.DISMISS -> AiTaskOverlayBridge.dismissNotification()
        }
    }
}
