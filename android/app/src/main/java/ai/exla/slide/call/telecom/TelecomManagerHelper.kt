package ai.exla.slide.call.telecom

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.annotation.RequiresPermission

/**
 * Registers Slide's self-managed [PhoneAccount] and surfaces incoming/outgoing
 * calls to the OS Telecom framework so they ring natively.
 */
object TelecomManagerHelper {

    private const val ACCOUNT_ID = "slide_self_managed"

    private fun handle(context: Context): PhoneAccountHandle =
        PhoneAccountHandle(ComponentName(context, SlideConnectionService::class.java), ACCOUNT_ID)

    fun registerPhoneAccount(context: Context) {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        val account = PhoneAccount.builder(handle(context), "Slide")
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .build()
        runCatching { tm.registerPhoneAccount(account) }
    }

    @RequiresPermission(android.Manifest.permission.MANAGE_OWN_CALLS)
    fun addIncomingCall(context: Context, callerName: String, callId: String) {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        val extras = Bundle().apply {
            putString(SlideConnectionService.EXTRA_CALLER_NAME, callerName)
            putString(SlideConnectionService.EXTRA_CALL_ID, callId)
        }
        runCatching { tm.addNewIncomingCall(handle(context), extras) }
    }

    @RequiresPermission(android.Manifest.permission.MANAGE_OWN_CALLS)
    fun placeOutgoingCall(context: Context, peerName: String, callId: String) {
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        val uri = Uri.fromParts("slide", callId, null)
        val extras = Bundle().apply {
            putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
            putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, Bundle().apply {
                putString(SlideConnectionService.EXTRA_CALLER_NAME, peerName)
                putString(SlideConnectionService.EXTRA_CALL_ID, callId)
            })
        }
        runCatching { tm.placeCall(uri, extras) }
    }
}
