package ai.exla.slide.messaging

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat

/**
 * Builds + posts the full-screen-intent incoming-call notification. On API 31+
 * it uses [NotificationCompat.CallStyle] so the system renders a native
 * phone-call style ringing UI; on older releases it falls back to a high-
 * priority notification with a full-screen intent. Either way the full-screen
 * intent launches [IncomingCallActivity] which shows over the lock screen.
 */
object IncomingCallNotifier {

    const val CHANNEL_ID = "slide_incoming_calls"
    const val NOTIFICATION_ID = 4711

    const val ACTION_ACCEPT = "ai.exla.slide.action.ACCEPT_CALL"
    const val ACTION_DECLINE = "ai.exla.slide.action.DECLINE_CALL"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Rings for incoming Slide calls and knocks"
            setShowBadge(false)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 700, 700, 700)
            val ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val audioAttrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(ringtone, audioAttrs)
        }
        nm.createNotificationChannel(channel)
    }

    fun showIncoming(context: Context, payload: IncomingCallPayload) {
        ensureChannel(context)

        // Full-screen intent: rings over the lock screen like a phone call.
        val fullScreenIntent = payload.putInto(
            Intent(context, IncomingCallActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        )
        val fullScreenPi = PendingIntent.getActivity(
            context,
            payload.callId.hashCode(),
            fullScreenIntent,
            pendingIntentFlags(mutable = false),
        )

        val acceptPi = actionPendingIntent(context, ACTION_ACCEPT, payload)
        val declinePi = actionPendingIntent(context, ACTION_DECLINE, payload)

        val callerLabel = if (payload.isKnock) "${payload.fromName} is knocking" else payload.fromName
        val subtitle = when {
            payload.isKnock -> "is knocking"
            payload.videoEnabled -> "Incoming video call"
            else -> "Incoming call"
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(callerLabel)
            .setContentText(subtitle)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPi, true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val caller = Person.Builder().setName(callerLabel).setImportant(true).build()
            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(caller, declinePi, acceptPi)
            )
        } else {
            builder
                .addAction(android.R.drawable.sym_call_outgoing, "Decline", declinePi)
                .addAction(android.R.drawable.sym_call_incoming, "Accept", acceptPi)
                .setContentIntent(fullScreenPi)
        }

        if (canPostNotifications(context)) {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        }
    }

    fun dismiss(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    private fun actionPendingIntent(
        context: Context,
        action: String,
        payload: IncomingCallPayload,
    ): PendingIntent {
        val intent = payload.putInto(
            Intent(context, CallActionReceiver::class.java).setAction(action)
        )
        return PendingIntent.getBroadcast(
            context,
            (action + payload.callId).hashCode(),
            intent,
            pendingIntentFlags(mutable = false),
        )
    }

    private fun pendingIntentFlags(mutable: Boolean): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        flags = flags or if (mutable) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        } else {
            PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
