package ai.exla.slide.call.telecom

import android.content.Context
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

/**
 * Telecom ConnectionService so Slide calls ring natively and integrate with the
 * system call UI / audio routing. Media is handled by [ai.exla.slide.call.CallService];
 * this glues into the OS call framework.
 */
class SlideConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        val connection = SlideConnection()
        // Conditional custom ringtone: use res/raw/ringtone if bundled, else the
        // system default ringtone. See res/raw/RINGTONE.md.
        connection.extras = Bundle(connection.extras ?: Bundle()).apply {
            putParcelable(EXTRA_RINGTONE_URI, ringtoneUri(this@SlideConnectionService))
        }
        connection.setRinging()
        connection.setCallerDisplayName(
            request?.extras?.getString(EXTRA_CALLER_NAME) ?: "Slide",
            TelecomManager.PRESENTATION_ALLOWED,
        )
        connection.connectionCapabilities = Connection.CAPABILITY_MUTE
        return connection
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ): Connection {
        return SlideConnection().apply { setDialing() }
    }

    companion object {
        const val EXTRA_CALLER_NAME = "ai.exla.slide.CALLER_NAME"
        const val EXTRA_CALL_ID = "ai.exla.slide.CALL_ID"
        const val EXTRA_RINGTONE_URI = "ai.exla.slide.RINGTONE_URI"

        /**
         * Resolves the incoming-call ringtone: the bundled `res/raw/ringtone` if
         * one was added at build time, otherwise the system default ringtone.
         */
        fun ringtoneUri(context: Context): Uri {
            val rawId = context.resources.getIdentifier("ringtone", "raw", context.packageName)
            return if (rawId != 0) {
                Uri.parse("android.resource://${context.packageName}/$rawId")
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            }
        }
    }
}

/**
 * A single Slide call connection. Bridges system call actions (answer, reject,
 * disconnect) onto the in-app call layer via [TelecomBridge].
 */
class SlideConnection : Connection() {

    init {
        audioModeIsVoip = true
        connectionProperties = PROPERTY_SELF_MANAGED
    }

    override fun onAnswer() {
        setActive()
        TelecomBridge.onAnswer?.invoke()
    }

    override fun onReject() {
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        TelecomBridge.onReject?.invoke()
    }

    override fun onDisconnect() {
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        TelecomBridge.onDisconnect?.invoke()
    }

    override fun onAbort() {
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        TelecomBridge.onDisconnect?.invoke()
    }
}

/**
 * Lightweight bridge so the app layer can react to system call-screen actions
 * without a hard dependency from the Telecom service into the UI graph.
 */
object TelecomBridge {
    var onAnswer: (() -> Unit)? = null
    var onReject: (() -> Unit)? = null
    var onDisconnect: (() -> Unit)? = null
}
