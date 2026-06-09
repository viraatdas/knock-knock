package ai.exla.slide.knock

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
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
 * Full-surface knock pad: a large circular ✊ target. Pressing it starts a real
 * call-style knock so the other phone can ring through the OS call UI.
 * Quiet & precise: white ground, thin ink type, the pad is the one bold element.
 */
@Composable
fun KnockPad(
    peer: CallPeer,
    onKnock: () -> Unit,
    onDone: () -> Unit,
) {
    val context = LocalContext.current
    val effects = remember { KnockEffects(context) }
    val scope = rememberCoroutineScope()
    val scale = remember { Animatable(1f) }
    val ringScale = remember { Animatable(1f) }
    val ringAlpha = remember { Animatable(0f) }
    var didStart by remember { mutableStateOf(false) }

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
            text = "Knock knock knock",
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
            modifier = Modifier.size(248.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(220.dp)
                    .scale(ringScale.value)
                    .alpha(ringAlpha.value)
                    .border(BorderStroke(1.dp, SlideColors.Ink), CircleShape),
            )
            Box(
                modifier = Modifier
                    .size(220.dp)
                    .scale(scale.value)
                    .background(SlideColors.Ink, CircleShape)
                    .clickable(
                        interactionSource = interaction,
                        indication = null,
                    ) {
                        if (didStart) return@clickable
                        didStart = true
                        effects.play()
                        onKnock()
                        scope.launch {
                            scale.snapTo(0.92f)
                            scale.animateTo(1f, tween(durationMillis = 180))
                        }
                        scope.launch {
                            ringScale.snapTo(0.96f)
                            ringAlpha.snapTo(0.45f)
                            ringScale.animateTo(1.34f, tween(durationMillis = 460))
                        }
                        scope.launch {
                            ringAlpha.animateTo(0f, tween(durationMillis = 460))
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(text = "✊", fontSize = 88.sp, color = SlideColors.Bg)
            }
        }

        Spacer(Modifier.height(24.dp))
        Text(
            text = "Knock to ring them with a slide-to-pick-up.",
            style = MaterialTheme.typography.bodyMedium,
            color = SlideColors.InkSecondary,
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.weight(1f))

        SecondaryButton(text = "Done", onClick = onDone)
        Spacer(Modifier.height(32.dp))
    }
}
