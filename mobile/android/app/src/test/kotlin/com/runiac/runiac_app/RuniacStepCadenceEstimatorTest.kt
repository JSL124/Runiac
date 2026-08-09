package com.runiac.runiac_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuniacStepCadenceEstimatorTest {
    @Test
    fun acceptsSlowBeginnerCadenceAtFortySpm() {
        val estimator = RuniacStepCadenceEstimator()

        val cadence = cadenceAfterThreeSteps(estimator, cadenceSpm = 40)

        assertEquals(40, cadence)
    }

    @Test
    fun rejectsCadenceBelowSupportedWalkingFloor() {
        val estimator = RuniacStepCadenceEstimator()

        val cadence = cadenceAfterThreeSteps(estimator, cadenceSpm = 39)

        assertNull(cadence)
    }

    @Test
    fun rejectsCadenceAboveSupportedRunningCeiling() {
        val estimator = RuniacStepCadenceEstimator()

        val cadence = cadenceAfterThreeSteps(estimator, cadenceSpm = 241)

        assertNull(cadence)
    }

    @Test
    fun acceptsCadenceAtSupportedRunningCeiling() {
        val estimator = RuniacStepCadenceEstimator()

        val cadence = cadenceAfterThreeSteps(estimator, cadenceSpm = 240)

        assertEquals(240, cadence)
    }

    @Test
    fun cadenceSampleEnvelopeIncludesStrictSampleType() {
        val event = cadenceSampleEvent(recordedAtMillis = 1234L, cadence = 120)

        assertEquals("sample", event["type"])
        assertEquals(1234L, event["recordedAtMillis"])
        assertEquals(120, event["stepsPerMinute"])
        assertEquals("estimated", event["confidence"])
    }

    private fun cadenceAfterThreeSteps(
        estimator: RuniacStepCadenceEstimator,
        cadenceSpm: Int,
    ): Int? {
        val intervalNanos = 60_000_000_000L / cadenceSpm
        var cadence: Int? = null
        for (index in 0 until 3) {
            cadence = estimator.cadenceFromStep(index * intervalNanos)
        }
        return cadence
    }
}
