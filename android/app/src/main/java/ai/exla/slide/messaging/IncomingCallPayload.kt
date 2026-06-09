package ai.exla.slide.messaging

import android.content.Intent
import android.os.Bundle

/**
 * Decoded incoming push payload. [type] is "incoming_call" or "knock"; a knock
 * is rendered like a call but labelled differently.
 */
data class IncomingCallPayload(
    val type: String,
    val callId: String,
    val fromUserId: String,
    val fromName: String,
    val callType: String,
    val videoEnabled: Boolean,
    val ringStyle: String,
) {
    val isKnock: Boolean get() = type == "knock" || ringStyle == "knock"

    fun putInto(intent: Intent): Intent = intent.apply {
        putExtra(EXTRA_TYPE, type)
        putExtra(EXTRA_CALL_ID, callId)
        putExtra(EXTRA_FROM_USER_ID, fromUserId)
        putExtra(EXTRA_FROM_NAME, fromName)
        putExtra(EXTRA_CALL_TYPE, callType)
        putExtra(EXTRA_VIDEO_ENABLED, videoEnabled)
        putExtra(EXTRA_RING_STYLE, ringStyle)
    }

    companion object {
        const val EXTRA_TYPE = "ai.exla.slide.push.TYPE"
        const val EXTRA_CALL_ID = "ai.exla.slide.push.CALL_ID"
        const val EXTRA_FROM_USER_ID = "ai.exla.slide.push.FROM_USER_ID"
        const val EXTRA_FROM_NAME = "ai.exla.slide.push.FROM_NAME"
        const val EXTRA_CALL_TYPE = "ai.exla.slide.push.CALL_TYPE"
        const val EXTRA_VIDEO_ENABLED = "ai.exla.slide.push.VIDEO_ENABLED"
        const val EXTRA_RING_STYLE = "ai.exla.slide.push.RING_STYLE"

        fun fromExtras(extras: Bundle?): IncomingCallPayload? {
            extras ?: return null
            val callId = extras.getString(EXTRA_CALL_ID) ?: return null
            return IncomingCallPayload(
                type = extras.getString(EXTRA_TYPE) ?: "incoming_call",
                callId = callId,
                fromUserId = extras.getString(EXTRA_FROM_USER_ID).orEmpty(),
                fromName = sanitizeCallerName(extras.getString(EXTRA_FROM_NAME)),
                callType = extras.getString(EXTRA_CALL_TYPE) ?: "one_to_one",
                videoEnabled = extras.videoEnabled(),
                ringStyle = extras.getString(EXTRA_RING_STYLE)
                    ?: if (extras.getString(EXTRA_TYPE) == "knock") "knock" else "call",
            )
        }

        @Suppress("DEPRECATION")
        private fun Bundle.videoEnabled(): Boolean {
            if (!containsKey(EXTRA_VIDEO_ENABLED)) return true
            val raw = get(EXTRA_VIDEO_ENABLED)
            return when (raw) {
                is Boolean -> raw
                is String -> raw.toBooleanStrictOrNull() ?: true
                else -> getBoolean(EXTRA_VIDEO_ENABLED, true)
            }
        }
    }
}

internal fun sanitizeCallerName(value: String?, fallback: String = "Slide"): String {
    val cleaned = value?.trim().orEmpty()
    if (cleaned.isBlank()) return fallback
    if (cleaned.equals("unknown", ignoreCase = true)) return fallback
    if (cleaned.equals("someone", ignoreCase = true)) return fallback
    return cleaned
}
