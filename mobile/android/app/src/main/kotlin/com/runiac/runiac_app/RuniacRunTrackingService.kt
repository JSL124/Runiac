package com.runiac.runiac_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

class RuniacRunTrackingService : Service() {
    private var latestDisplay = RunNotificationDisplay.default()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                latestDisplay = RunNotificationDisplay.fromIntent(intent, latestDisplay)
                startForegroundTracking()
            }
            ACTION_UPDATE -> {
                latestDisplay = RunNotificationDisplay.fromIntent(intent, latestDisplay)
                updateNotification()
            }
            ACTION_STOP -> {
                stopForegroundTracking()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundTracking() {
        if (!hasLocationPermission()) {
            stopSelf()
            return
        }

        ensureChannel()
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            } else {
                0
            },
        )
    }

    private fun updateNotification() {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun stopForegroundTracking() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val display = latestDisplay
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(display.title)
            .setContentText(display.body)
            .setCustomContentView(buildCollapsedView(display))
            .setCustomBigContentView(buildExpandedView(display))
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(buildContentIntent())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun buildCollapsedView(display: RunNotificationDisplay): RemoteViews {
        return RemoteViews(
            packageName,
            R.layout.runiac_run_tracking_notification_collapsed,
        ).apply {
            setTextViewText(R.id.runiac_collapsed_title, display.title)
            setTextViewText(R.id.runiac_collapsed_body, display.body)
        }
    }

    private fun buildExpandedView(display: RunNotificationDisplay): RemoteViews {
        return RemoteViews(
            packageName,
            R.layout.runiac_run_tracking_notification_expanded,
        ).apply {
            setTextViewText(R.id.runiac_expanded_status, display.statusLabel)
            setTextViewText(R.id.runiac_metric_time, display.elapsedTimeLabel)
            setTextViewText(R.id.runiac_metric_average_pace, display.averagePaceLabel)
            setTextViewText(R.id.runiac_metric_distance, display.distanceLabel)
            val supportCopy = display.supportCopy
            if (supportCopy.isNullOrBlank()) {
                setViewVisibility(R.id.runiac_support_copy, View.GONE)
            } else {
                setViewVisibility(R.id.runiac_support_copy, View.VISIBLE)
                setTextViewText(R.id.runiac_support_copy, supportCopy)
            }
        }
    }

    private fun buildContentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_RUN_OPEN_INTENT, RUN_OPEN_INTENT_NOTIFICATION)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(this, REQUEST_CODE_OPEN_RUN, intent, flags)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESCRIPTION
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        const val ACTION_START = "com.runiac.runiac_app.run_tracking.START"
        const val ACTION_UPDATE = "com.runiac.runiac_app.run_tracking.UPDATE"
        const val ACTION_STOP = "com.runiac.runiac_app.run_tracking.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_STATUS_LABEL = "statusLabel"
        const val EXTRA_ELAPSED_TIME_LABEL = "elapsedTimeLabel"
        const val EXTRA_AVERAGE_PACE_LABEL = "averagePaceLabel"
        const val EXTRA_DISTANCE_LABEL = "distanceLabel"
        const val EXTRA_SUPPORT_COPY = "supportCopy"
        const val EXTRA_RUN_OPEN_INTENT = "runiac_run_open_intent"
        const val RUN_OPEN_INTENT_NOTIFICATION = "notification"

        private const val CHANNEL_ID = "runiac_run_tracking"
        private const val CHANNEL_NAME = "Runiac Run Tracking"
        private const val CHANNEL_DESCRIPTION =
            "Shows active run tracking while Runiac records your route."
        private const val NOTIFICATION_ID = 41024
        private const val REQUEST_CODE_OPEN_RUN = 41025
        private const val DEFAULT_TITLE = "Runiac is tracking your run"
        private const val DEFAULT_BODY = "00:00 • --:-- /km • 0.00 km"
        private const val DEFAULT_STATUS_LABEL = "Getting GPS ready"
        private const val DEFAULT_ELAPSED_TIME_LABEL = "00:00"
        private const val DEFAULT_AVERAGE_PACE_LABEL = "--:-- /km"
        private const val DEFAULT_DISTANCE_LABEL = "0.00 km"
        private const val DEFAULT_SUPPORT_COPY = "Keep moving in an open area."
    }

    private data class RunNotificationDisplay(
        val title: String,
        val body: String,
        val statusLabel: String,
        val elapsedTimeLabel: String,
        val averagePaceLabel: String,
        val distanceLabel: String,
        val supportCopy: String?,
    ) {
        companion object {
            fun default(): RunNotificationDisplay {
                return RunNotificationDisplay(
                    title = DEFAULT_TITLE,
                    body = DEFAULT_BODY,
                    statusLabel = DEFAULT_STATUS_LABEL,
                    elapsedTimeLabel = DEFAULT_ELAPSED_TIME_LABEL,
                    averagePaceLabel = DEFAULT_AVERAGE_PACE_LABEL,
                    distanceLabel = DEFAULT_DISTANCE_LABEL,
                    supportCopy = DEFAULT_SUPPORT_COPY,
                )
            }

            fun fromIntent(
                intent: Intent,
                fallback: RunNotificationDisplay,
            ): RunNotificationDisplay {
                return RunNotificationDisplay(
                    title = intent.getStringExtra(EXTRA_TITLE) ?: fallback.title,
                    body = intent.getStringExtra(EXTRA_BODY) ?: fallback.body,
                    statusLabel = intent.getStringExtra(EXTRA_STATUS_LABEL)
                        ?: fallback.statusLabel,
                    elapsedTimeLabel = intent.getStringExtra(EXTRA_ELAPSED_TIME_LABEL)
                        ?: fallback.elapsedTimeLabel,
                    averagePaceLabel = intent.getStringExtra(EXTRA_AVERAGE_PACE_LABEL)
                        ?: fallback.averagePaceLabel,
                    distanceLabel = intent.getStringExtra(EXTRA_DISTANCE_LABEL)
                        ?: fallback.distanceLabel,
                    supportCopy = if (intent.hasExtra(EXTRA_SUPPORT_COPY)) {
                        intent.getStringExtra(EXTRA_SUPPORT_COPY)
                    } else {
                        fallback.supportCopy
                    },
                )
            }
        }
    }
}
