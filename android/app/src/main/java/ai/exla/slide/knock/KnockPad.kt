package ai.exla.slide.knock

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.exla.slide.call.CallPeer
import ai.exla.slide.ui.components.SecondaryButton
import ai.exla.slide.ui.theme.SlideColors
import kotlinx.coroutines.launch

/**
 * Full-surface knock pad: a large circular ✊ tap target. Each tap relays a knock
 * to [peer] and plays local sound + haptic so the sender feels their own rhythm.
 * Quiet & precise: white ground, thin ink type, the pad is the one bold element.
 */
@Composable
fun KnockPad(
    peer: CallPeer,
    vm: KnockViewModel,
    onDone: () -> Unit,
) {
    val context = LocalContext.current
    val effects = remember { KnockEffects(context) }
    val scope = rememberCoroutineScope()
    val scale = remember { Animatable(1f) }

    LaunchedEffect(peer.userId) { vm.startPattern() }
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { effects.release() }
    }

    val title = peer.displayName?.takeIf { it.isNotBlank() } ?: peer.phone ?: "Slide"

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(72.dp))
        Text(
            text = "Knocking",
            style = MaterialTheme.typography.labelLarge,
            color = SlideColors.InkSecondary,
        )
        Spacer(Modifier.height(6.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            color = SlideColors.Ink,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.weight(1f))

        val interaction = remember { MutableInteractionSource() }
        Box(
            modifier = Modifier
                .size(220.dp)
                .scale(scale.value)
                .background(SlideColors.Ink, CircleShape)
                .clickable(
                    interactionSource = interaction,
                    indication = null,
                ) {
                    vm.tap(peer.userId)
                    effects.play()
                    scope.launch {
                        scale.snapTo(0.92f)
                        scale.animateTo(1f, tween(durationMillis = 180))
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(text = "✊", fontSize = 88.sp, color = SlideColors.Bg)
        }

        Spacer(Modifier.height(24.dp))
        Text(
            text = "Tap a rhythm. They feel each knock.",
            style = MaterialTheme.typography.bodyMedium,
            color = SlideColors.InkSecondary,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.weight(1f))

        SecondaryButton(text = "Done", onClick = onDone)
        Spacer(Modifier.height(32.dp))
    }
}
