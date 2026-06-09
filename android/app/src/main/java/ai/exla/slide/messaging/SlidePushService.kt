package ai.exla.slide.messaging

import ai.exla.slide.SlideApp
import ai.exla.slide.call.telecom.SlideConnectionService
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Receives FCM events and turns a high-priority **data** message into a
 * full-screen incoming-call notification that rings over the lock screen.
 *
 * Inert until Firebase is wired up: this service is only ever instantiated by
 * the Firebase SDK, which never starts unless a FirebaseApp was initialized
 * (i.e. google-services.json + the google-services plugin are present). Until
 * then it is dead code that simply compiles.
 *
 * Expected data payload (all string values, FCM data is always strings):
 *   type       -> "incoming_call" | "knock" | "call_ended" | "call_declined"
 *   callId     -> call id (or knock correlation id)
 *   fromUserId -> caller's user id
 *   fromName   -> caller's display name
 *   callType   -> "one_to_one" | "group" (optional; defaults to one_to_one)
 *
 * Send these as a `data` message (NOT `notification`) with priority "high" so
 * Android delivers it even in Doze / when the app is killed, and so this
 * handler runs to post the full-screen-intent notification.
 */
class SlidePushService : FirebaseMessagingService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Register the refreshed token with the backend (best-effort). Only
        // attempts when signed in; the repo no-ops on a blank token.
        val repo = (application as? SlideApp)?.container?.repository ?: return
        scope.launch { repo.registerDevice(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        val type = data["type"]?.takeIf { it.isNotBlank() } ?: return
        if (type == "call_ended" || type == "call_declined") {
            IncomingCallNotifier.dismiss(this)
            SlideConnectionService.endActiveConnectionFromRemote()
            return
        }
        if (type != "incoming_call" && type != "knock") return

        val callId = data["callId"]?.takeIf { it.isNotBlank() } ?: return
        IncomingCallNotifier.showIncoming(
            context = this,
            payload = IncomingCallPayload(
                type = type,
                callId = callId,
                fromUserId = data["fromUserId"].orEmpty(),
                fromName = sanitizeCallerName(data["fromName"]),
                callType = data["callType"]?.takeIf { it.isNotBlank() } ?: "one_to_one",
                videoEnabled = data["videoEnabled"]?.toBooleanStrictOrNull() ?: true,
                ringStyle = data["ringStyle"]?.takeIf { it.isNotBlank() }
                    ?: if (data["knock"]?.toBooleanStrictOrNull() == true || type == "knock") "knock" else "call",
            ),
        )
    }
}
