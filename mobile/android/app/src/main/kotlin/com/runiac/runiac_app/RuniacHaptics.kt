package com.runiac.runiac_app

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.RequiresApi

/**
 * Semantic haptic levels mirrored from Dart's `RuniacHaptics`.
 *
 * The wire names are the exact strings the Dart side sends over the
 * `runiac/haptics` channel, so they must stay in sync with
 * `lib/core/haptics/runiac_haptics.dart`.
 */
internal enum class RuniacHapticKind(val wireName: String) {
    SELECTION("selection"),
    LIGHT_IMPACT("lightImpact"),
    MEDIUM_IMPACT("mediumImpact"),
    HEAVY_IMPACT("heavyImpact"),
    ERROR("error"),
    ;

    companion object {
        fun fromWireName(wireName: String?): RuniacHapticKind? =
            entries.firstOrNull { it.wireName == wireName }
    }
}

/**
 * Plays Runiac's semantic haptics through the platform vibrator.
 *
 * Flutter's own `HapticFeedback` maps every level onto
 * `View.performHapticFeedback` touch-tick constants (`CLOCK_TICK`,
 * `VIRTUAL_KEY`, `KEYBOARD_TAP`, `CONTEXT_CLICK`). Those are the same class of
 * effect the software keyboard uses: barely perceptible on an LRA device and
 * frequently a no-op on rotational (ERM) motors, which is why runners reported
 * feeling nothing outside the error case. Driving the vibrator directly lets
 * each level carry a real, distinguishable strength.
 *
 * Effects are tagged with the touch usage, so a runner who has turned off
 * system-level touch feedback still gets silence — that setting is deliberately
 * respected rather than bypassed.
 *
 * Every level degrades across three hardware tiers:
 *  - API 30+ with composition primitives: crisp, individually scaled haptics.
 *  - API 29+: OEM-tuned predefined effects (medium and heavy collapse onto
 *    `EFFECT_HEAVY_CLICK`, the strongest predefined effect available).
 *  - API 26+: one-shot/waveform effects, using amplitude when the motor
 *    supports it and duration alone when it does not.
 *  - Below API 26: legacy duration-only vibration.
 */
internal class RuniacHaptics(context: Context) {
    private val appContext: Context = context.applicationContext

    private val vibrator: Vibrator? by lazy { resolveVibrator() }

    private val supportsPrimitives: Boolean by lazy {
        val target = vibrator ?: return@lazy false
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            target.areAllPrimitivesSupported(
                VibrationEffect.Composition.PRIMITIVE_CLICK,
                VibrationEffect.Composition.PRIMITIVE_TICK,
            )
    }

    /**
     * Plays [kind], or does nothing when the device has no usable vibrator.
     *
     * Haptics are a non-critical comfort feature, so any platform failure is
     * swallowed rather than surfaced to the calling Flutter feature flow.
     */
    fun play(kind: RuniacHapticKind) {
        val target = vibrator ?: return
        if (!target.hasVibrator()) {
            return
        }
        try {
            when {
                supportsPrimitives -> target.playEffect(composedEffect(kind))
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    target.playEffect(predefinedEffect(kind))
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                    target.playEffect(oneShotEffect(kind, target.hasAmplitudeControl()))
                else -> target.playLegacy(kind)
            }
        } catch (error: RuntimeException) {
            // A missing/blocked vibrator must never break the calling feature.
        }
    }

    private fun resolveVibrator(): Vibrator? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    } catch (error: RuntimeException) {
        null
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun Vibrator.playEffect(effect: VibrationEffect) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrate(effect, touchVibrationAttributes())
        } else {
            @Suppress("DEPRECATION")
            vibrate(effect, TOUCH_AUDIO_ATTRIBUTES)
        }
    }

    private fun Vibrator.playLegacy(kind: RuniacHapticKind) {
        @Suppress("DEPRECATION")
        if (kind == RuniacHapticKind.ERROR) {
            vibrate(ERROR_PATTERN_MS, LEGACY_NO_REPEAT, TOUCH_AUDIO_ATTRIBUTES)
        } else {
            vibrate(durationMsFor(kind), TOUCH_AUDIO_ATTRIBUTES)
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun touchVibrationAttributes(): VibrationAttributes =
        VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH)

    /**
     * The best tier: each level is a scaled primitive, so selection reads as a
     * faint tick and a milestone reads as a full thud.
     */
    @RequiresApi(Build.VERSION_CODES.R)
    private fun composedEffect(kind: RuniacHapticKind): VibrationEffect {
        val composition = VibrationEffect.startComposition()
        when (kind) {
            RuniacHapticKind.SELECTION ->
                composition.addPrimitive(
                    VibrationEffect.Composition.PRIMITIVE_TICK,
                    SELECTION_SCALE,
                )
            RuniacHapticKind.LIGHT_IMPACT ->
                composition.addPrimitive(
                    VibrationEffect.Composition.PRIMITIVE_CLICK,
                    LIGHT_SCALE,
                )
            RuniacHapticKind.MEDIUM_IMPACT ->
                composition.addPrimitive(
                    VibrationEffect.Composition.PRIMITIVE_CLICK,
                    MEDIUM_SCALE,
                )
            RuniacHapticKind.HEAVY_IMPACT ->
                composition
                    .addPrimitive(
                        VibrationEffect.Composition.PRIMITIVE_CLICK,
                        HEAVY_SCALE,
                    )
                    .addPrimitive(
                        VibrationEffect.Composition.PRIMITIVE_TICK,
                        HEAVY_TAIL_SCALE,
                        HEAVY_TAIL_DELAY_MS,
                    )
            RuniacHapticKind.ERROR ->
                composition
                    .addPrimitive(
                        VibrationEffect.Composition.PRIMITIVE_CLICK,
                        ERROR_SCALE,
                    )
                    .addPrimitive(
                        VibrationEffect.Composition.PRIMITIVE_CLICK,
                        ERROR_SCALE,
                        ERROR_GAP_MS,
                    )
        }
        return composition.compose()
    }

    /**
     * Mid tier. Only four predefined effects exist, so medium and heavy share
     * the strongest one; the light/strong contrast still survives.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun predefinedEffect(kind: RuniacHapticKind): VibrationEffect =
        VibrationEffect.createPredefined(
            when (kind) {
                RuniacHapticKind.SELECTION -> VibrationEffect.EFFECT_TICK
                RuniacHapticKind.LIGHT_IMPACT -> VibrationEffect.EFFECT_CLICK
                RuniacHapticKind.MEDIUM_IMPACT -> VibrationEffect.EFFECT_HEAVY_CLICK
                RuniacHapticKind.HEAVY_IMPACT -> VibrationEffect.EFFECT_HEAVY_CLICK
                RuniacHapticKind.ERROR -> VibrationEffect.EFFECT_DOUBLE_CLICK
            },
        )

    /**
     * Lowest tier. Devices without amplitude control (typically ERM motors)
     * only get the duration ramp, which reads as a shorter or longer buzz.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun oneShotEffect(
        kind: RuniacHapticKind,
        hasAmplitudeControl: Boolean,
    ): VibrationEffect {
        if (kind == RuniacHapticKind.ERROR) {
            return if (hasAmplitudeControl) {
                VibrationEffect.createWaveform(
                    ERROR_PATTERN_MS,
                    ERROR_PATTERN_AMPLITUDES,
                    LEGACY_NO_REPEAT,
                )
            } else {
                VibrationEffect.createWaveform(ERROR_PATTERN_MS, LEGACY_NO_REPEAT)
            }
        }
        return VibrationEffect.createOneShot(
            durationMsFor(kind),
            if (hasAmplitudeControl) {
                amplitudeFor(kind)
            } else {
                VibrationEffect.DEFAULT_AMPLITUDE
            },
        )
    }

    private fun durationMsFor(kind: RuniacHapticKind): Long = when (kind) {
        RuniacHapticKind.SELECTION -> SELECTION_DURATION_MS
        RuniacHapticKind.LIGHT_IMPACT -> LIGHT_DURATION_MS
        RuniacHapticKind.MEDIUM_IMPACT -> MEDIUM_DURATION_MS
        RuniacHapticKind.HEAVY_IMPACT -> HEAVY_DURATION_MS
        RuniacHapticKind.ERROR -> MEDIUM_DURATION_MS
    }

    private fun amplitudeFor(kind: RuniacHapticKind): Int = when (kind) {
        RuniacHapticKind.SELECTION -> SELECTION_AMPLITUDE
        RuniacHapticKind.LIGHT_IMPACT -> LIGHT_AMPLITUDE
        RuniacHapticKind.MEDIUM_IMPACT -> MEDIUM_AMPLITUDE
        RuniacHapticKind.HEAVY_IMPACT -> HEAVY_AMPLITUDE
        RuniacHapticKind.ERROR -> MEDIUM_AMPLITUDE
    }

    companion object {
        private const val SELECTION_SCALE = 0.4f
        private const val LIGHT_SCALE = 0.5f
        private const val MEDIUM_SCALE = 0.8f
        private const val HEAVY_SCALE = 1.0f
        private const val HEAVY_TAIL_SCALE = 0.6f
        private const val ERROR_SCALE = 0.7f
        private const val HEAVY_TAIL_DELAY_MS = 30
        private const val ERROR_GAP_MS = 90

        private const val SELECTION_DURATION_MS = 10L
        private const val LIGHT_DURATION_MS = 15L
        private const val MEDIUM_DURATION_MS = 25L
        private const val HEAVY_DURATION_MS = 40L

        private const val SELECTION_AMPLITUDE = 60
        private const val LIGHT_AMPLITUDE = 100
        private const val MEDIUM_AMPLITUDE = 180
        private const val HEAVY_AMPLITUDE = 255

        private const val LEGACY_NO_REPEAT = -1
        private val ERROR_PATTERN_MS = longArrayOf(0L, 30L, 90L, 30L)
        private val ERROR_PATTERN_AMPLITUDES = intArrayOf(0, 180, 0, 180)

        private val TOUCH_AUDIO_ATTRIBUTES: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }
}
