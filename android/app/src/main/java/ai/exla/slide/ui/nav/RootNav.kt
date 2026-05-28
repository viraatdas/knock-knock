package ai.exla.slide.ui.nav

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import ai.exla.slide.AppContainer
import ai.exla.slide.call.CallPeer
import ai.exla.slide.ui.VmFactory
import ai.exla.slide.ui.incall.InCallScreen
import ai.exla.slide.ui.incall.InCallViewModel
import ai.exla.slide.ui.onboarding.AuthStep
import ai.exla.slide.ui.onboarding.AuthViewModel
import ai.exla.slide.ui.onboarding.CodeScreen
import ai.exla.slide.ui.onboarding.NameScreen
import ai.exla.slide.ui.onboarding.PhoneScreen
import ai.exla.slide.ui.onboarding.WelcomeScreen

/** Top-level app state: which major surface is showing. */
private sealed interface RootScreen {
    data object Auth : RootScreen
    data object Main : RootScreen
    data class InCall(val peer: CallPeer) : RootScreen
}

@Composable
fun SlideAppRoot(container: AppContainer) {
    var screen by remember {
        mutableStateOf<RootScreen>(
            if (container.tokenStore.isLoggedIn) RootScreen.Main else RootScreen.Auth
        )
    }

    when (val current = screen) {
        RootScreen.Auth -> AuthFlow(
            container = container,
            onAuthenticated = { screen = RootScreen.Main },
        )

        RootScreen.Main -> {
            // Connect the app signaling socket while logged in.
            androidx.compose.runtime.LaunchedEffect(Unit) { container.signalingClient.connect() }
            MainShell(
                container = container,
                onStartCall = { peer -> screen = RootScreen.InCall(peer) },
                onLoggedOut = {
                    container.signalingClient.disconnect()
                    screen = RootScreen.Auth
                },
            )
        }

        is RootScreen.InCall -> {
            val factory = VmFactory(container)
            val vm: InCallViewModel = viewModel(factory = factory)
            androidx.compose.runtime.LaunchedEffect(current.peer.userId) {
                // Mock service renders immediately; real impl performs POST /calls.
                vm.placeCall(current.peer)
            }
            InCallScreen(vm = vm, onEnded = { screen = RootScreen.Main })
        }
    }
}

@Composable
private fun AuthFlow(container: AppContainer, onAuthenticated: () -> Unit) {
    val factory = VmFactory(container)
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
