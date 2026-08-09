package com.runiac.runiac_app

import kotlin.math.roundToInt

internal class RuniacStepCadenceEstimator {
    private val stepTimestamps = ArrayDeque<Long>()

    fun reset() {
        stepTimestamps.clear()
    }

    fun cadenceFromStep(timestampNanos: Long): Int? {
        stepTimestamps.addLast(timestampNanos)
        val windowStart = timestampNanos - CADENCE_WINDOW_NANOS
        while (stepTimestamps.isNotEmpty() && stepTimestamps.first() < windowStart) {
            stepTimestamps.removeFirst()
        }
        if (stepTimestamps.size < MINIMUM_WINDOW_STEPS) {
            return null
        }
        val firstTimestamp = stepTimestamps.first()
        val elapsedMinutes = (timestampNanos - firstTimestamp).toDouble() /
            NANOS_PER_MINUTE
        if (elapsedMinutes <= 0) {
            return null
        }
        val cadence = ((stepTimestamps.size - 1) / elapsedMinutes).roundToInt()
        if (cadence < MINIMUM_CADENCE_SPM || cadence > MAXIMUM_CADENCE_SPM) {
            return null
        }
        return cadence
    }

    companion object {
        private const val CADENCE_WINDOW_NANOS = 5_000_000_000L
        private const val NANOS_PER_MINUTE = 60_000_000_000.0
        private const val MINIMUM_WINDOW_STEPS = 3
        internal const val MINIMUM_CADENCE_SPM = 40
        internal const val MAXIMUM_CADENCE_SPM = 240
    }
}
