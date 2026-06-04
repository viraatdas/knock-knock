package ai.exla.slide.ui.nav

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import ai.exla.slide.AppContainer
import ai.exla.slide.call.CallPeer
import ai.exla.slide.call.telecom.TelecomBridge
import ai.exla.slide.call.telecom.TelecomManagerHelper
import ai.exla.slide.call.telecom.SlideConnectionService
import ai.exla.slide.data.model.SignalEnvelope
import ai.exla.slide.ui.VmFactory
import ai.exla.slide.ui.incall.InCallScreen
import ai.exla.slide.ui.incall.InCallViewModel
import ai.exla.slide.ui.incall.IncomingCallScreen
import ai.exla.slide.ui.onboarding.AuthStep
import ai.exla.slide.ui.onboarding.AuthViewModel
import ai.exla.slide.ui.onboarding.CodeScreen
import ai.exla.slide.ui.onboarding.NameScreen
import ai.exla.slide.ui.onboarding.PhoneScreen
import ai.exla.slide.ui.onboarding.WelcomeScreen
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Top-level app state: which major surface is showing. */
private sealed interface RootScreen {
    data object Auth : RootScreen
    data object Main : RootScreen
    data class Incoming(val callId: String, val peer: CallPeer) : RootScreen
    data class InCall(val peer: CallPeer, val incomingCallId: String? = null) : RootScreen
}

@Composable
fun SlideAppRoot(container: AppContainer) {
    val context = LocalContext.current
    val factory = remember(container) { VmFactory(container) }
    val scope = rememberCoroutineScope()
    var screen by remember {
        mutableStateOf<RootScreen>(
            if (container.tokenStore.isLoggedIn) RootScreen.Main else RootScreen.Auth
        )
    }

    LaunchedEffect(screen is RootScreen.Auth) {
        if (screen is RootScreen.Auth) {
            container.signalingClient.disconnect()
            return@LaunchedEffect
        }

        container.signalingClient.connect()
        container.signalingClient.events.collect { event ->
            when (event.type) {
                "incoming_call" -> {
                    val incoming = event.toIncomingScreen() ?: return@collect
                    TelecomManagerHelper.addIncomingCall(
                        context,
                        incoming.peer.displayName ?: incoming.peer.phone ?: "Slide",
                        incoming.callId,
                    )
                    screen = incoming
                }
                "call_ended", "call_declined" -> {
                    val eventCallId = event.callId ?: event.call?.id
                    when (val current = screen) {
                        is RootScreen.Incoming ->
                            if (current.callId == eventCallId) screen = RootScreen.Main
                        is RootScreen.InCall ->
                            if (current.incomingCallId == eventCallId) screen = RootScreen.Main
                        else -> Unit
                    }
                }
            }
        }
    }

    when (val current = screen) {
        RootScreen.Auth -> AuthFlow(
            container = container,
            onAuthenticated = { screen = RootScreen.Main },
        )

        RootScreen.Main -> {
            MainShell(
                container = container,
                onStartCall = { peer -> screen = RootScreen.InCall(peer) },
                onLoggedOut = {
                    container.signalingClient.disconnect()
                    screen = RootScreen.Auth
                },
            )
        }

        is RootScreen.Incoming -> {
            fun declineIncoming(updateTelecom: Boolean) {
                if (updateTelecom) SlideConnectionService.rejectActiveConnection()
                scope.launch {
                    container.repository.declineCall(current.callId)
                    screen = RootScreen.Main
                }
            }

            DisposableEffect(current.callId) {
                TelecomBridge.onAnswer = {
                    scope.launch { screen = RootScreen.InCall(current.peer, current.callId) }
                }
                TelecomBridge.onReject = { declineIncoming(updateTelecom = false) }
                TelecomBridge.onDisconnect = { declineIncoming(updateTelecom = false) }
                onDispose {
                    TelecomBridge.onAnswer = null
                    TelecomBridge.onReject = null
                    TelecomBridge.onDisconnect = null
                }
            }

            IncomingCallScreen(
                peer = current.peer,
                onAccept = {
                    SlideConnectionService.answerActiveConnection()
                    screen = RootScreen.InCall(current.peer, current.callId)
                },
                onDecline = { declineIncoming(updateTelecom = true) },
            )
        }

        is RootScreen.InCall -> {
            val vm: InCallViewModel = viewModel(factory = factory)
            LaunchedEffect(current.peer.userId, current.incomingCallId) {
                if (current.incomingCallId != null) {
                    vm.acceptCall(current.incomingCallId, current.peer)
                } else {
                    // Mock service renders immediately; real impl performs POST /calls.
                    vm.placeCall(current.peer)
                }
            }
            DisposableEffect(current.incomingCallId) {
                TelecomBridge.onDisconnect = {
                    scope.launch { vm.end { screen = RootScreen.Main } }
                }
                onDispose {
                    TelecomBridge.onDisconnect = null
                    if (current.incomingCallId != null) {
                        SlideConnectionService.disconnectActiveConnection()
                    }
                }
            }
            InCallScreen(vm = vm, onEnded = { screen = RootScreen.Main })
        }
    }
}

@Composable
private fun AuthFlow(container: AppContainer, onAuthenticated: () -> Unit) {
    val factory = remember(container) { VmFactory(container) }
    val vm: AuthViewModel = viewModel(factory = factory)
    val state by vm.state.collectAsStateWithLifecycle()

    when (state.step) {
        AuthStep.Welcome -> WelcomeScreen(onGetStarted = vm::goToPhone)
        AuthStep.Phone -> PhoneScreen(vm)
        AuthStep.Code -> CodeScreen(vm, onAuthenticated = { onAuthenticated() })
        AuthStep.Name -> NameScreen(vm, onDone = onAuthenticated)
        AuthStep.Done -> onAuthenticated()
    }
}

private fun SignalEnvelope.toIncomingScreen(): RootScreen.Incoming? {
    val id = callId ?: call?.id ?: return null
    val callerId = fromUserId
        ?: (from as? JsonPrimitive)?.contentOrNull
        ?: (from as? JsonObject)?.get("id")?.jsonPrimitive?.contentOrNull
        ?: call?.createdBy
        ?: "unknown"
    val name = fromName
        ?: (from as? JsonObject)?.get("displayName")?.jsonPrimitive?.contentOrNull
        ?: (from as? JsonObject)?.get("phone")?.jsonPrimitive?.contentOrNull
        ?: "Slide"
    val phone = (from as? JsonObject)?.get("phone")?.jsonPrimitive?.contentOrNull
    return RootScreen.Incoming(
        callId = id,
        peer = CallPeer(
            userId = callerId,
            displayName = name,
            phone = phone,
        ),
    )
}
