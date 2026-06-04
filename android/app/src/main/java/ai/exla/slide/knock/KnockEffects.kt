package ai.exla.slide.knock

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * Asset-free knock feedback: a short device buzz plus a synthesized low "thud"
 * for each tap. No audio/vibration resource files — the waveform is generated at
 * runtime so a knock "feels" the same on both ends without shipping any media.
 *
 * Reuse one instance per surface; call [play] on every tap (sent or received)
 * and [release] when the surface goes away.
 */
class KnockEffects(context: Context) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val vibrator: Vibrator? = run {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = appContext.getSystemService(VibratorManager::class.java)
            mgr?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    /** Pre-rendered thud PCM so each tap is instant (no per-tap synth cost). */
    private val thudPcm: ShortArray by lazy { synthThud() }

    /** Play a single knock: ~35ms haptic tick + a short low thud. */
    fun play() {
        vibrate()
        scope.launch { playThud() }
    }

    private fun vibrate() {
        val v = vibrator ?: return
        if (!v.hasVibrator()) return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createOneShot(35L, VibrationEffect.DEFAULT_AMPLITUDE)
                v.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(35L)
            }
        }
    }

    private fun playThud() {
        runCatching {
            val track = AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
                thudPcm.size * 2,
                AudioTrack.MODE_STATIC,
                AudioManager.AUDIO_SESSION_ID_GENERATE,
            )
            track.write(thudPcm, 0, thudPcm.size)
            track.setNotificationMarkerPosition(thudPcm.size)
            track.setPlaybackPositionUpdateListener(
                object : AudioTrack.OnPlaybackPositionUpdateListener {
                    override fun onMarkerReached(t: AudioTrack?) {
                        runCatching { t?.stop() }
                        runCatching { t?.release() }
                    }

                    override fun onPeriodicNotification(t: AudioTrack?) {}
                }
            )
            track.play()
        }
    }

    /** Decaying ~150Hz sine, ~150ms — a soft, low knock thud. */
    private fun synthThud(): ShortArray {
        val frames = (SAMPLE_RATE * DURATION_MS / 1000)
        val out = ShortArray(frames)
        val twoPiF = 2.0 * PI * FREQ_HZ
        for (i in 0 until frames) {
            val t = i.toDouble() / SAMPLE_RATE
            // Fast exponential decay so it reads as a tap, not a tone.
            val env = exp(-t * DECAY)
            val sample = sin(twoPiF * t) * env * AMPLITUDE
            out[i] = (sample * Short.MAX_VALUE).toInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }
        return out
    }

    fun release() {
        scope.coroutineContext[kotlinx.coroutines.Job]?.cancel()
    }

    private companion object {
        const val SAMPLE_RATE = 44_100
        const val DURATION_MS = 150
        const val FREQ_HZ = 150.0
        const val DECAY = 22.0
        const val AMPLITUDE = 0.9
    }
}
