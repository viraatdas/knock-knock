package ai.exla.slide.messaging

import ai.exla.slide.SlideApp
import ai.exla.slide.call.CallPeer
import ai.exla.slide.ui.VmFactory
import ai.exla.slide.ui.incall.InCallScreen
import ai.exla.slide.ui.incall.InCallViewModel
import ai.exla.slide.ui.incall.IncomingCallScreen
import ai.exla.slide.ui.theme.SlideTheme
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModelProvider

/**
 * Full-screen incoming-call surface launched by the push notification's
 * full-screen intent. Shows over the lock screen and turns the screen on so an
 * incoming call/knock rings like a phone call even when the device is locked.
 *
 * Renders the existing [IncomingCallScreen]; on accept it routes into the call
 * via the existing [InCallViewModel] + [InCallScreen] path. The notification's
 * Accept action launches this activity with [EXTRA_AUTO_ACCEPT] so it jumps
 * straight to the in-call screen.
 */
class IncomingCallActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        enableEdgeToEdge()

        val payload = IncomingCallPayload.fromExtras(intent.extras)
        if (payload == null) {
            finish()
            return
        }
        IncomingCallNotifier.dismiss(this)

        val container = (application as SlideApp).container
        val factory = VmFactory(container)
        val vm = ViewModelProvider(this, factory)[InCallViewModel::class.java]
        val peer = CallPeer(
            userId = payload.fromUserId,
            displayName = payload.fromName,
        )
        val autoAccept = intent.getBooleanExtra(EXTRA_AUTO_ACCEPT, false)

        setContent {
            SlideTheme {
                var accepted by remember { mutableStateOf(autoAccept) }

                if (accepted) {
                    // Join the call through the existing accept path, then show
                    // the in-call UI. Audio knocks reuse the same call surface.
                    androidx.compose.runtime.LaunchedEffect(payload.callId) {
                        vm.acceptCall(payload.callId, peer, payload.videoEnabled)
                    }
                    InCallScreen(vm = vm, onEnded = { finish() })
                } else {
                    IncomingCallScreen(
                        peer = peer,
                        videoEnabled = payload.videoEnabled,
                        isKnock = payload.isKnock,
                        onAccept = { accepted = true },
                        onDecline = { vm.decline(payload.callId) { finish() } },
                    )
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            keyguard?.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    companion object {
        const val EXTRA_AUTO_ACCEPT = "ai.exla.slide.push.AUTO_ACCEPT"
    }
}
