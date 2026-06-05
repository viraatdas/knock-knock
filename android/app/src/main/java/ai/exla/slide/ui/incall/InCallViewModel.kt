package ai.exla.slide.ui.incall

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.call.CallPeer
import ai.exla.slide.call.CallService
import ai.exla.slide.call.CallUiState
import ai.exla.slide.call.StartCallRequest
import ai.exla.slide.data.model.Call
import ai.exla.slide.data.repo.SlideRepository
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Drives the in-call screen. Delegates media to [CallService] and call-control
 * (accept/decline/leave) to the REST API via [SlideRepository].
 */
class InCallViewModel(
    private val repo: SlideRepository,
    private val callService: CallService,
) : ViewModel() {

    val state: StateFlow<CallUiState> = callService.state

    /** Place an outgoing one-to-one call to a peer user. */
    fun placeCall(peer: CallPeer) {
        viewModelScope.launch {
            repo.createCall(peer.userId).onSuccess { session ->
                callService.start(StartCallRequest(session, peer, isIncoming = false))
            }
        }
    }

    /** Accept an incoming call by id. */
    fun acceptCall(callId: String, peer: CallPeer) {
        viewModelScope.launch {
            repo.acceptCall(callId).onSuccess { session ->
                callService.start(StartCallRequest(session, peer, isIncoming = true))
            }
        }
    }

    /** Decline a ringing incoming call. */
    fun decline(callId: String, onDone: () -> Unit) {
        viewModelScope.launch {
            repo.declineCall(callId)
            onDone()
        }
    }

    fun toggleMic() = callService.toggleMic()
    fun toggleCamera() = callService.toggleCamera()
    fun flipCamera() = callService.flipCamera()

    /** End/leave the active call. */
    fun end(onDone: () -> Unit) {
        val callId = callService.state.value.callId
        callService.end()
        viewModelScope.launch {
            callId?.let { repo.leaveCall(it) }
            onDone()
        }
    }

    fun localTrack() = callService.localVideoTrack()
    fun remoteTrack() = callService.remoteVideoTrack()
    fun room() = callService.room()

    /** Convenience used by previews/demo: start a mock call to a peer. */
    fun startMockCall(peer: CallPeer) {
        callService.start(
            StartCallRequest(
                session = ai.exla.slide.data.model.CallSession(
                    call = Call(id = "demo", status = "active"),
                    joinToken = "demo",
                    sfuUrl = "wss://demo",
                ),
                peer = peer,
                isIncoming = false,
            )
        )
    }
}
