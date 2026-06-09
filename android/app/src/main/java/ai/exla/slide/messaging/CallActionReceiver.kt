package ai.exla.slide.messaging

import ai.exla.slide.SlideApp
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Handles the Accept / Decline actions on the incoming-call notification. Works
 * even when the app process was killed (the receiver is cold-started by the
 * notification action).
 *
 *  - Accept  -> dismiss the notification and launch [IncomingCallActivity] with
 *               an auto-accept flag, which routes into the existing call path.
 *  - Decline -> dismiss the notification and POST the backend decline.
 */
class CallActionReceiver : BroadcastReceiver() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onReceive(context: Context, intent: Intent) {
        val payload = IncomingCallPayload.fromExtras(intent.extras) ?: return
        IncomingCallNotifier.dismiss(context)

        when (intent.action) {
            IncomingCallNotifier.ACTION_ACCEPT -> {
                val launch = payload.putInto(
                    Intent(context, IncomingCallActivity::class.java).apply {
                        putExtra(IncomingCallActivity.EXTRA_AUTO_ACCEPT, true)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    }
                )
                context.startActivity(launch)
            }

            IncomingCallNotifier.ACTION_DECLINE -> {
                val repo = (context.applicationContext as? SlideApp)?.container?.repository
                if (repo != null) {
                    val pending = goAsync()
                    scope.launch {
                        runCatching { repo.declineCall(payload.callId) }
                        pending.finish()
                    }
                }
            }
        }
    }
}
