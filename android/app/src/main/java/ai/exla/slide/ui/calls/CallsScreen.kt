package ai.exla.slide.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.CallMade
import androidx.compose.material.icons.automirrored.outlined.CallReceived
import androidx.compose.material.icons.outlined.Dialpad
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.call.CallPeer
import ai.exla.slide.data.model.Call
import ai.exla.slide.data.model.CallParticipant
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.EmptyState
import ai.exla.slide.ui.components.Hairline
import ai.exla.slide.ui.components.quietClickable
import ai.exla.slide.ui.theme.SlideColors
import ai.exla.slide.util.relativeTime

@Composable
fun CallsScreen(
    vm: CallsViewModel,
    currentUserId: String?,
    onNewCall: () -> Unit,
    onCallBack: (CallPeer, Boolean) -> Unit,
    onKnock: (CallPeer) -> Unit,
) {
    val state by vm.state.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .padding(horizontal = 20.dp),
    ) {
        // Top bar: wordmark + new-call icon.
        Row(
            modifier = Modifier.fillMaxWidth().height(64.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Slide",
                color = SlideColors.Ink,
                fontWeight = FontWeight.Light,
                letterSpacing = 1.2.sp,
                fontSize = 28.sp,
            )
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier.size(44.dp).quietClickable(onNewCall),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Dialpad, "Open callpad", tint = SlideColors.Ink, modifier = Modifier.size(25.dp))
            }
        }

        when {
            state.loading && state.calls.isEmpty() ->
                EmptyState("", Modifier.fillMaxSize())
            state.calls.isEmpty() ->
                EmptyState("No calls yet", Modifier.fillMaxSize())
            else -> LazyColumn(Modifier.fillMaxSize()) {
                items(state.calls, key = { it.id }) { call ->
                    CallRow(
                        call = call,
                        currentUserId = currentUserId,
                        onCallBack = onCallBack,
                        onKnock = onKnock,
                    )
                    Hairline(startInset = 56.dp)
                }
            }
        }
    }
}

@Composable
private fun CallRow(
    call: Call,
    currentUserId: String?,
    onCallBack: (CallPeer, Boolean) -> Unit,
    onKnock: (CallPeer) -> Unit,
) {
    val other = otherParticipant(call, currentUserId)
    val display = displayNameFor(call, currentUserId)
    val peer = CallPeer(
        userId = other?.userId ?: call.createdBy ?: "",
        displayName = display,
        phone = other?.phone,
        avatarUrl = other?.avatarUrl,
    )

    // Incoming if someone else created the call.
    val incoming = call.createdBy != null && call.createdBy != currentUserId
    val missed = call.status == "missed"
    val declined = call.status == "declined"

    val subtitleColor = if (missed) SlideColors.Danger else SlideColors.InkSecondary
    val subtitle = buildString {
        append(if (incoming) "Incoming" else "Outgoing")
        when {
            missed -> { clear(); append("Missed") }
            declined -> append(" · Declined")
        }
        append(" · ")
        append(relativeTime(call.startedAt ?: call.createdAt))
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(72.dp)
            .quietClickable { onKnock(peer) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarCircle(name = display, size = 40.dp)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(display, style = MaterialTheme.typography.bodyLarge, color = SlideColors.Ink)
            Spacer(Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (incoming) {
                        Icons.AutoMirrored.Outlined.CallReceived
                    } else {
                        Icons.AutoMirrored.Outlined.CallMade
                    },
                    contentDescription = null,
                    tint = subtitleColor,
                    modifier = Modifier.size(14.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = subtitleColor)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .border(1.dp, SlideColors.Hairline, CircleShape)
                    .quietClickable { onKnock(peer) },
                contentAlignment = Alignment.Center,
            ) {
                Text("✊", fontSize = 17.sp)
            }
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .quietClickable { onCallBack(peer, call.videoEnabled) },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (call.videoEnabled) Icons.Outlined.Videocam else Icons.Outlined.Phone,
                    contentDescription = if (call.videoEnabled) "Video call back" else "Call back",
                    tint = SlideColors.Ink,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
}

private fun displayNameFor(call: Call, currentUserId: String?): String {
    val other = otherParticipant(call, currentUserId)
    return other?.displayName?.cleanDisplayName()
        ?: other?.phone?.takeIf { it.isNotBlank() }
        ?: "Slide"
}

private fun otherParticipant(call: Call, currentUserId: String?): CallParticipant? {
    return call.participants.firstOrNull { it.userId != currentUserId }
        ?: call.participants.firstOrNull { it.userId == call.createdBy }
        ?: call.participants.firstOrNull()
}

private fun String?.cleanDisplayName(): String? {
    val cleaned = this?.trim().orEmpty()
    if (cleaned.isBlank()) return null
    if (cleaned.equals("unknown", ignoreCase = true)) return null
    if (cleaned.equals("someone", ignoreCase = true)) return null
    return cleaned
}
