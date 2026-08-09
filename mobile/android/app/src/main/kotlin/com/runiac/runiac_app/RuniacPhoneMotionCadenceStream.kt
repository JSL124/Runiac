package com.runiac.runiac_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

internal fun cadenceSampleEvent(
    recordedAtMillis: Long,
    cadence: Int,
): Map<String, Any> =
    mapOf(
        "type" to "sample",
        "recordedAtMillis" to recordedAtMillis,
        "stepsPerMinute" to cadence,
        "confidence" to "estimated",
    )

class RuniacPhoneMotionCadenceStream(
    private val context: Context,
) : EventChannel.StreamHandler, SensorEventListener {
    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val cadenceEstimator = RuniacStepCadenceEstimator()
    private var eventSink: EventChannel.EventSink? = null

    fun isAvailable(): Boolean {
        return hasPermission() &&
            sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (!isAvailable()) {
            events?.endOfStream()
            return
        }
        val stepDetector = sensorManager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        if (stepDetector == null) {
            events?.endOfStream()
            return
        }
        cadenceEstimator.reset()
        sensorManager.registerListener(
            this,
            stepDetector,
            SensorManager.SENSOR_DELAY_NORMAL,
        )
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        cadenceEstimator.reset()
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_STEP_DETECTOR) {
            return
        }
        val cadence = cadenceEstimator.cadenceFromStep(event.timestamp) ?: return
        eventSink?.success(cadenceSampleEvent(System.currentTimeMillis(), cadence))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun hasPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED
    }

}
