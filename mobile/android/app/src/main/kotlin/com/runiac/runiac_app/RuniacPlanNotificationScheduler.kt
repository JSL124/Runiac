package com.runiac.runiac_app

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class RuniacPlanNotificationScheduler(private val context: Context) {
    /**
     * Invoked when a notification is presented while a Flutter engine happens
     * to be attached, so the unread badge can update without waiting for the
     * next resume. Null in the receiver's cold-start case, which is exactly
     * why the delivery is persisted rather than only announced.
     */
    var deliveryListener: (() -> Unit)? = null

    fun syncPlanNotifications(arguments: Any?) {
        cancelPlanNotifications()
        val notifications = notificationsFromArguments(arguments)
        saveScheduledIds(notifications.map { it.id }.toSet())
        for (notification in notifications) {
            scheduleNotification(notification)
        }
    }

    fun schedulePlanNotification(arguments: Any?) {
        val notification = notificationFromItem(arguments) ?: return
        scheduleNotification(notification)
    }

    fun cancelPlanNotifications() {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (id in scheduledIds()) {
            pendingIntentFor(id, PendingIntent.FLAG_NO_CREATE)?.let { pendingIntent ->
                alarmManager.cancel(pendingIntent)
            }
            notificationManager.cancel(notificationIdFor(id))
        }
        saveScheduledIds(emptySet())
    }

    fun showNotificationFromIntent(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val body = intent.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
        showNotification(id, title, body)
    }

    private fun scheduleNotification(notification: PlanNotificationPayload) {
        if (notification.scheduledAtMillis <= System.currentTimeMillis()) {
            return
        }
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, RuniacPlanNotificationReceiver::class.java).apply {
            action = ACTION_SHOW_PLAN_NOTIFICATION
            putExtra(EXTRA_ID, notification.id)
            putExtra(EXTRA_TITLE, notification.title)
            putExtra(EXTRA_BODY, notification.body)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationIdFor(notification.id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            notification.scheduledAtMillis,
            pendingIntent,
        )
    }

    private fun showNotification(id: String, title: String, body: String) {
        if (!canShowNotifications()) {
            return
        }
        ensureChannel()
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(
            notificationIdFor(id),
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(openAppPendingIntent())
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build(),
        )
        recordDelivery(id, System.currentTimeMillis())
        deliveryListener?.invoke()
    }

    /**
     * Persists the fact that a notification was actually presented.
     *
     * This is the only trustworthy delivery signal on Android: the alarm fires
     * into [RuniacPlanNotificationReceiver], which can cold-start the process
     * with no Flutter engine attached, so nothing can be handed to Dart at this
     * moment. The record waits in SharedPreferences until Dart drains it
     * through [consumeDeliveredNotifications].
     */
    private fun recordDelivery(id: String, deliveredAtMillis: Long) {
        val existing = deliveryRecords()
        val trimmed = (existing + "$id$DELIVERY_FIELD_SEPARATOR$deliveredAtMillis")
            .takeLast(MAX_DELIVERY_RECORDS)
        preferences().edit()
            .putString(DELIVERED_EVENTS_KEY, trimmed.joinToString(DELIVERY_RECORD_SEPARATOR))
            .apply()
    }

    /** Returns every recorded delivery and clears the store in one step. */
    fun consumeDeliveredNotifications(): List<Map<String, Any>> {
        val records = deliveryRecords()
        if (records.isEmpty()) {
            return emptyList()
        }
        preferences().edit().remove(DELIVERED_EVENTS_KEY).apply()
        return records.mapNotNull { record ->
            val separatorIndex = record.lastIndexOf(DELIVERY_FIELD_SEPARATOR)
            if (separatorIndex <= 0) {
                return@mapNotNull null
            }
            val id = record.substring(0, separatorIndex)
            val deliveredAtMillis =
                record.substring(separatorIndex + 1).toLongOrNull()
                    ?: return@mapNotNull null
            mapOf("id" to id, "deliveredAtMillis" to deliveredAtMillis)
        }
    }

    private fun deliveryRecords(): List<String> {
        val raw = preferences().getString(DELIVERED_EVENTS_KEY, null)
        if (raw.isNullOrEmpty()) {
            return emptyList()
        }
        return raw.split(DELIVERY_RECORD_SEPARATOR).filter { it.isNotEmpty() }
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            OPEN_APP_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
    }

    private fun pendingIntentFor(id: String, flags: Int): PendingIntent? {
        val intent = Intent(context, RuniacPlanNotificationReceiver::class.java).apply {
            action = ACTION_SHOW_PLAN_NOTIFICATION
        }
        return PendingIntent.getBroadcast(
            context,
            notificationIdFor(id),
            intent,
            flags or immutableFlag(),
        )
    }

    private fun canShowNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = CHANNEL_DESCRIPTION
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun notificationsFromArguments(arguments: Any?): List<PlanNotificationPayload> {
        val root = arguments as? Map<*, *> ?: return emptyList()
        val rawNotifications = root["notifications"] as? List<*> ?: return emptyList()
        return rawNotifications.mapNotNull(::notificationFromItem)
    }

    private fun notificationFromItem(item: Any?): PlanNotificationPayload? {
        val rawNotification = item as? Map<*, *> ?: return null
        val id = rawNotification["id"] as? String ?: return null
        val title = rawNotification["title"] as? String ?: return null
        val body = rawNotification["body"] as? String ?: return null
        val scheduledAtMillis = rawNotification["scheduledAtMillis"] as? Number ?: return null
        return PlanNotificationPayload(
            id = id,
            title = title,
            body = body,
            scheduledAtMillis = scheduledAtMillis.toLong(),
        )
    }

    private fun scheduledIds(): Set<String> {
        return preferences().getStringSet(SCHEDULED_IDS_KEY, emptySet()) ?: emptySet()
    }

    private fun saveScheduledIds(ids: Set<String>) {
        preferences().edit().putStringSet(SCHEDULED_IDS_KEY, ids).apply()
    }

    private fun preferences() = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    private fun immutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    private fun notificationIdFor(id: String): Int = id.hashCode()

    private data class PlanNotificationPayload(
        val id: String,
        val title: String,
        val body: String,
        val scheduledAtMillis: Long,
    )

    companion object {
        private const val ACTION_SHOW_PLAN_NOTIFICATION =
            "com.runiac.runiac_app.plan_notifications.SHOW"
        private const val EXTRA_ID = "id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val CHANNEL_ID = "runiac_plan_reminders"
        private const val CHANNEL_NAME = "Runiac Plan Reminders"
        private const val CHANNEL_DESCRIPTION =
            "Reminds you before and after scheduled Runiac plans."
        private const val DEFAULT_TITLE = "Runiac plan reminder"
        private const val DEFAULT_BODY = "Open Runiac to view today's plan."
        private const val OPEN_APP_REQUEST_CODE = 51240
        private const val PREFERENCES_NAME = "runiac_plan_notifications"
        private const val SCHEDULED_IDS_KEY = "scheduled_ids"
        private const val DELIVERED_EVENTS_KEY = "delivered_events"
        private const val DELIVERY_RECORD_SEPARATOR = "\n"
        private const val DELIVERY_FIELD_SEPARATOR = '\u0001'
        private const val MAX_DELIVERY_RECORDS = 200
    }
}
