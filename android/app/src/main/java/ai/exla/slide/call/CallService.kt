package ai.exla.slide.call

import io.livekit.android.room.Room
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.flow.StateFlow

/**
 * Abstraction over the WebRTC media engine. The UI talks only to this interface
 * so it can render against either the real [WebRtcCallService] or the
 * [MockCallService] (the default, so the app renders without a device or live
 * SFU).
 */
interface CallService {

    /** Observable call state for the in-call screen. */
    val state: StateFlow<CallUiState>

    /** Connect to the SFU using the session's sfuUrl + joinToken + iceServers. */
    fun start(request: StartCallRequest)

    /** Tear down the peer connection and release media. */
    fun end()

    fun toggleMic(): Boolean
    fun toggleCamera(): Boolean
    fun flipCamera()

    /** Local self-view track. Null until camera capture starts (always in mock). */
    fun localVideoTrack(): VideoTrack?

    /** Remote participant's video track once it arrives from the SFU. */
    fun remoteVideoTrack(): VideoTrack?

    /** The LiveKit room backing the call (null for the mock), needed to bind a
     *  renderer to a track in the UI. */
    fun room(): Room?
}
