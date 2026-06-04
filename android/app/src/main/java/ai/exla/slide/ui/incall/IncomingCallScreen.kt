package ai.exla.slide.ui.incall

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CallEnd
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.exla.slide.call.CallPeer
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.CircleIconButton
import ai.exla.slide.ui.theme.SlideColors

/**
 * Full-white incoming-call screen: large avatar + name, with a gentle pulse
 * (1.0 → 1.04). Black Accept, red Decline. (AGENTS.md)
 */
@Composable
fun IncomingCallScreen(
    peer: CallPeer,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
) {
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(
            animation = tween(900),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulseScale",
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .systemBarsPadding()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        AvatarCircle(
            name = peer.displayName,
            size = 128.dp,
            modifier = Modifier.scale(pulse),
        )
        Spacer(Modifier.height(24.dp))
        Text(
            peer.displayName ?: peer.phone ?: "Unknown",
            color = SlideColors.Ink,
            fontWeight = FontWeight.Light,
            fontSize = 30.sp,
        )
        Spacer(Modifier.height(8.dp))
        Text("Incoming call", color = SlideColors.InkSecondary, fontSize = 15.sp)
        Spacer(Modifier.weight(1f))

        Row(
            modifier = Modifier.fillMaxWidth().padding(bottom = 48.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircleIconButton(
                    icon = Icons.Outlined.CallEnd,
                    contentDescription = "Decline",
                    onClick = onDecline,
                    diameter = 72.dp,
                    filled = true,
                    color = SlideColors.Danger,
                )
                Spacer(Modifier.height(10.dp))
                Text("Decline", color = SlideColors.InkSecondary, fontSize = 13.sp)
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircleIconButton(
                    icon = Icons.Outlined.Phone,
                    contentDescription = "Accept",
                    onClick = onAccept,
                    diameter = 72.dp,
                    filled = true,
                    color = SlideColors.Ink,
                )
                Spacer(Modifier.height(10.dp))
                Text("Accept", color = SlideColors.InkSecondary, fontSize = 13.sp)
            }
        }
    }
}
