package ai.exla.slide.ui.incall

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.VideocamOff
import androidx.compose.material.icons.outlined.CallEnd
import androidx.compose.material.icons.outlined.Cameraswitch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.call.CallConnectionState
import ai.exla.slide.call.CallUiState
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.CircleIconButton
import ai.exla.slide.ui.theme.SlideColors
import ai.exla.slide.util.formatDuration
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Composable
fun InCallScreen(vm: InCallViewModel, onEnded: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()

    LaunchedEffect(state.connection) {
        if (state.connection == CallConnectionState.Ended ||
            state.connection == CallConnectionState.Failed
        ) {
            onEnded()
        }
    }

    // Chrome auto-hides after a few seconds; tap to reveal.
    var chromeVisible by remember { mutableStateOf(true) }
    LaunchedEffect(chromeVisible, state.connection) {
        if (chromeVisible && state.connection == CallConnectionState.Connected) {
            delay(4000)
            chromeVisible = false
        }
    }

    val onVideoSurface = !state.audioOnly && state.remoteVideoActive

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(if (state.audioOnly) SlideColors.Bg else SlideColors.Ink)
            .pointerInput(Unit) {
                detectTapGestures { chromeVisible = !chromeVisible }
            },
    ) {
        if (!onVideoSurface) {
            AudioOnlyStage(state)
        } else {
            // Full-bleed remote video renders behind the chrome; a
            // SurfaceViewRenderer is bound in the real WebRTC implementation.
            Box(Modifier.fillMaxSize().background(SlideColors.Ink))
            DraggableSelfView()
        }

        AnimatedVisibility(
            visible = chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter),
        ) {
            TopChrome(state, onVideoSurface)
        }

        AnimatedVisibility(
            visible = chromeVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter),
        ) {
            ControlBar(
                state = state,
                onVideoSurface = onVideoSurface,
                onMute = { vm.toggleMic() },
                onFlip = { vm.flipCamera() },
                onVideo = { vm.toggleCamera() },
                onEnd = { vm.end(onEnded) },
            )
        }
    }
}

@Composable
private fun AudioOnlyStage(state: CallUiState) {
    Column(
        modifier = Modifier.fillMaxSize().systemBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        AvatarCircle(name = state.peer?.displayName, size = 120.dp)
        Spacer(Modifier.height(24.dp))
        Text(
            state.peer?.displayName ?: "Calling…",
            color = SlideColors.Ink,
            fontWeight = FontWeight.Light,
            fontSize = 28.sp,
        )
        Spacer(Modifier.height(8.dp))
        Text(statusText(state), color = SlideColors.InkSecondary, fontSize = 15.sp)
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun TopChrome(state: CallUiState, onVideoSurface: Boolean) {
    val tint = if (onVideoSurface) SlideColors.OnVideo else SlideColors.Ink
    Column(
        modifier = Modifier.fillMaxWidth().systemBarsPadding().padding(top = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            state.peer?.displayName ?: "",
            color = tint,
            fontWeight = FontWeight.Light,
            fontSize = 20.sp,
        )
        Spacer(Modifier.height(4.dp))
        Text(statusText(state), color = tint.copy(alpha = 0.8f), fontSize = 14.sp)
    }
}

@Composable
private fun ControlBar(
    state: CallUiState,
    onVideoSurface: Boolean,
    onMute: () -> Unit,
    onFlip: () -> Unit,
    onVideo: () -> Unit,
    onEnd: () -> Unit,
) {
    val tint = if (onVideoSurface) SlideColors.OnVideo else SlideColors.Ink

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .systemBarsPadding()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircleIconButton(
            icon = if (state.micEnabled) Icons.Filled.Mic else Icons.Filled.MicOff,
            contentDescription = "Mute",
            onClick = onMute,
            diameter = 56.dp,
            color = tint,
        )
        CircleIconButton(
            icon = Icons.Outlined.Cameraswitch,
            contentDescription = "Flip camera",
            onClick = onFlip,
            diameter = 56.dp,
            color = tint,
        )
        CircleIconButton(
            icon = if (state.cameraEnabled) Icons.Filled.Videocam else Icons.Filled.VideocamOff,
            contentDescription = "Camera on/off",
            onClick = onVideo,
            diameter = 56.dp,
            color = tint,
        )
        CircleIconButton(
            icon = Icons.Outlined.CallEnd,
            contentDescription = "End call",
            onClick = onEnd,
            diameter = 64.dp,
            filled = true,
            color = SlideColors.Danger,
        )
    }
}

/** Rounded, draggable local self-view in the corner. */
@Composable
private fun DraggableSelfView() {
    var offset by remember { mutableStateOf(Offset.Zero) }

    Box(
        modifier = Modifier
            .systemBarsPadding()
            .padding(16.dp)
            .offset { IntOffset(offset.x.roundToInt(), offset.y.roundToInt()) }
            .size(108.dp, 160.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(SlideColors.InkSecondary.copy(alpha = 0.4f))
            .pointerInput(Unit) {
                // Self-contained drag using only the ui-layer pointer API.
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: continue
                        if (change.pressed) {
                            val delta = change.position - change.previousPosition
                            offset += delta
                            change.consume()
                        }
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        AvatarCircle(name = "Me", size = 56.dp, backgroundColor = SlideColors.Bg)
    }
}

private fun statusText(state: CallUiState): String = when (state.connection) {
    CallConnectionState.Connecting -> "Connecting…"
    CallConnectionState.Connected -> formatDuration(state.durationSec)
    CallConnectionState.Ended -> "Call ended"
    CallConnectionState.Failed -> "Call failed"
    CallConnectionState.Idle -> "Calling…"
}
