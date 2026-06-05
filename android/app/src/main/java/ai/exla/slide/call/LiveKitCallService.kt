package ai.exla.slide.call

import android.content.Context
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.track.LocalVideoTrack
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Real media via the self-hosted **LiveKit** SFU. The control plane (`/calls`)
 * returns `session.sfuUrl` (LiveKit ws URL) + `session.joinToken` (a LiveKit
 * access token scoped to room = call id); both participants join the same room.
 *
 * Replaces the old custom-SFU [PeerConnection] client (webrtc-rs SFU couldn't
 * complete DTLS over real networks). LiveKit handles ICE/DTLS/TURN + a TCP
 * fallback, so calls connect even on UDP-restricted networks.
 */
class LiveKitCallService(private val appContext: Context) : CallService {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ticker: Job? = null

    private val _state = MutableStateFlow(CallUiState())
    override val state: StateFlow<CallUiState> = _state.asStateFlow()

    private val room: Room = LiveKit.create(appContext)
    private var localVideo: VideoTrack? = null
    private var remoteVideo: VideoTrack? = null

    override fun start(request: StartCallRequest) {
        _state.value = CallUiState(
            callId = request.session.call.id,
            peer = request.peer,
            connection = CallConnectionState.Connecting,
            isIncoming = request.isIncoming,
        )
        // Observe room + media events (connection state + tracks).
        scope.launch { room.events.collect { onRoomEvent(it) } }

        scope.launch {
            runCatching {
                room.connect(request.session.sfuUrl, request.session.joinToken)
                room.localParticipant.setMicrophoneEnabled(true)
                room.localParticipant.setCameraEnabled(true)
                localVideo = room.localParticipant
                    .getTrackPublication(Track.Source.CAMERA)?.track as? VideoTrack
            }.onFailure {
                _state.update { s -> s.copy(connection = CallConnectionState.Failed) }
            }
        }
    }

    private fun onRoomEvent(event: RoomEvent) {
        when (event) {
            is RoomEvent.Connected -> onConnected()
            is RoomEvent.Disconnected ->
                _state.update { it.copy(connection = CallConnectionState.Ended) }
            is RoomEvent.Reconnecting ->
                _state.update { it.copy(connection = CallConnectionState.Connecting) }
            is RoomEvent.TrackSubscribed -> {
                (event.track as? VideoTrack)?.let { track ->
                    remoteVideo = track
                    _state.update { it.copy(remoteVideoActive = true, audioOnly = false) }
                }
            }
            is RoomEvent.TrackUnsubscribed -> {
                if (event.track == remoteVideo) {
                    remoteVideo = null
                    _state.update { it.copy(remoteVideoActive = false) }
                }
            }
            else -> Unit
        }
    }

    private fun onConnected() {
        _state.update { it.copy(connection = CallConnectionState.Connected) }
        ticker?.cancel()
        ticker = scope.launch {
            while (true) {
                delay(1000)
                _state.update { it.copy(durationSec = it.durationSec + 1) }
            }
        }
    }

    /* ---------------- Controls ---------------- */

    override fun toggleMic(): Boolean {
        val next = !_state.value.micEnabled
        scope.launch { runCatching { room.localParticipant.setMicrophoneEnabled(next) } }
        _state.update { it.copy(micEnabled = next) }
        return next
    }

    override fun toggleCamera(): Boolean {
        val next = !_state.value.cameraEnabled
        scope.launch { runCatching { room.localParticipant.setCameraEnabled(next) } }
        _state.update { it.copy(cameraEnabled = next) }
        return next
    }

    override fun flipCamera() {
        (localVideo as? LocalVideoTrack)?.let { track ->
            scope.launch { runCatching { track.switchCamera() } }
        }
        _state.update { it.copy(usingFrontCamera = !it.usingFrontCamera) }
    }

    override fun localVideoTrack(): VideoTrack? = localVideo
    override fun remoteVideoTrack(): VideoTrack? = remoteVideo
    override fun room(): Room = room

    override fun end() {
        ticker?.cancel()
        runCatching { room.disconnect() }
        _state.update { it.copy(connection = CallConnectionState.Ended) }
    }
}
