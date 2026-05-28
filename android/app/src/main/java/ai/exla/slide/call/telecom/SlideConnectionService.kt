package ai.exla.slide.call.telecom

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
