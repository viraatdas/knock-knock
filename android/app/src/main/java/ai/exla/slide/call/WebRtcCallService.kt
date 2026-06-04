package ai.exla.slide.call

import android.content.Context
import ai.exla.slide.data.model.IceServer
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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.webrtc.AudioTrack
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoCapturer
import org.webrtc.VideoSource
import org.webrtc.VideoTrack

/**
 * Real WebRTC implementation. Builds a [PeerConnectionFactory], captures
 * camera + mic, connects to the SFU at `sfuUrl` (plane B) authenticated with
 * `joinToken`, configures the provided `iceServers`, and runs the SDP
 * offer/answer + ICE trickle exchange.
 *
 * The media pipeline (capture, encode, tracks, ICE) is fully wired. The exact
 * on-wire signaling field names are defined by the SFU (AGENTS.md) and may
 * need alignment once it is available — which cannot be verified in this
 * environment without a device + live SFU. The app therefore defaults to
 * [MockCallService] for rendering.
 */
class WebRtcCallService(
    private val appContext: Context,
    private val json: Json = Json { ignoreUnknownKeys = true },
) : CallService {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var ticker: Job? = null

    private val _state = MutableStateFlow(CallUiState())
    override val state: StateFlow<CallUiState> = _state.asStateFlow()

    private val eglBase: EglBase by lazy { EglBase.create() }
    fun eglBaseContext(): EglBase.Context = eglBase.eglBaseContext

    private var factory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var ws: WebSocket? = null

    private var videoCapturer: VideoCapturer? = null
    private var videoSource: VideoSource? = null
    private var surfaceHelper: SurfaceTextureHelper? = null
    private var localVideoTrack: VideoTrack? = null
    private var localAudioTrack: AudioTrack? = null
    private var remoteVideoTrack: VideoTrack? = null

    private val httpClient = OkHttpClient.Builder().build()

    private fun ensureFactory() {
        if (factory != null) return
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(appContext)
                .createInitializationOptions()
        )
        val encoder = DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true)
        val decoder = DefaultVideoDecoderFactory(eglBase.eglBaseContext)
        factory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoder)
            .setVideoDecoderFactory(decoder)
            .createPeerConnectionFactory()
    }

    override fun start(request: StartCallRequest) {
        _state.value = CallUiState(
            callId = request.session.call.id,
            peer = request.peer,
            connection = CallConnectionState.Connecting,
            isIncoming = request.isIncoming,
        )
        scope.launch {
            runCatching {
                ensureFactory()
                createPeerConnection(request.session.iceServers)
                startLocalMedia()
                connectSfu(request.session.sfuUrl, request.session.joinToken)
            }.onFailure {
                _state.update { s -> s.copy(connection = CallConnectionState.Failed) }
            }
        }
    }

    private fun createPeerConnection(ice: List<IceServer>) {
        val iceServers = ice.map { server ->
            val builder = PeerConnection.IceServer.builder(server.urls)
            server.username?.let { builder.setUsername(it) }
            server.credential?.let { builder.setPassword(it) }
            builder.createIceServer()
        }
        val config = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy =
                PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
        }

        peerConnection = factory?.createPeerConnection(config, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) = sendCandidate(candidate)

            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                (receiver.track() as? VideoTrack)?.let { track ->
                    remoteVideoTrack = track
                    _state.update { it.copy(remoteVideoActive = true, audioOnly = false) }
                }
            }

            override fun onConnectionChange(newState: PeerConnection.PeerConnectionState) {
                when (newState) {
                    PeerConnection.PeerConnectionState.CONNECTED -> onConnected()
                    PeerConnection.PeerConnectionState.FAILED ->
                        _state.update { it.copy(connection = CallConnectionState.Failed) }
                    PeerConnection.PeerConnectionState.DISCONNECTED,
                    PeerConnection.PeerConnectionState.CLOSED ->
                        _state.update { it.copy(connection = CallConnectionState.Ended) }
                    else -> Unit
                }
            }

            override fun onSignalingChange(p0: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(p0: PeerConnection.IceConnectionState?) {}
            override fun onIceConnectionReceivingChange(p0: Boolean) {}
            override fun onIceGatheringChange(p0: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}
            override fun onAddStream(p0: MediaStream?) {}
            override fun onRemoveStream(p0: MediaStream?) {}
            override fun onDataChannel(p0: org.webrtc.DataChannel?) {}
            override fun onRenegotiationNeeded() {}
        })
    }

    private fun startLocalMedia() {
        val pcFactory = factory ?: return

        val audioSource = pcFactory.createAudioSource(MediaConstraints())
        localAudioTrack = pcFactory.createAudioTrack("audio0", audioSource).also {
            peerConnection?.addTrack(it, listOf("stream0"))
        }

        val capturer = createCameraCapturer(front = true)
        if (capturer != null) {
            videoCapturer = capturer
            surfaceHelper = SurfaceTextureHelper.create("CaptureThread", eglBase.eglBaseContext)
            val source = pcFactory.createVideoSource(capturer.isScreencast)
            videoSource = source
            capturer.initialize(surfaceHelper, appContext, source.capturerObserver)
            capturer.startCapture(1280, 720, 30)
            localVideoTrack = pcFactory.createVideoTrack("video0", source).also {
                it.setEnabled(true)
                peerConnection?.addTrack(it, listOf("stream0"))
            }
        }
    }

    private fun createCameraCapturer(front: Boolean): CameraVideoCapturer? {
        val enumerator = Camera2Enumerator(appContext)
        val names = enumerator.deviceNames
        names.firstOrNull { enumerator.isFrontFacing(it) == front }?.let {
            return enumerator.createCapturer(it, null)
        }
        return names.firstOrNull()?.let { enumerator.createCapturer(it, null) }
    }

    /* ---------------- SFU signaling (plane B) ---------------- */

    private fun connectSfu(sfuUrl: String, joinToken: String) {
        val request = Request.Builder()
            .url(sfuUrl)
            .addHeader("Authorization", "Bearer $joinToken")
            .build()
        ws = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = createOffer()
            override fun onMessage(webSocket: WebSocket, text: String) = handleSignal(text)
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _state.update { it.copy(connection = CallConnectionState.Failed) }
            }
        })
    }

    private fun createOffer() {
        val pc = peerConnection ?: return
        pc.createOffer(object : SimpleSdpObserver() {
            override fun onCreateSuccess(desc: SessionDescription) {
                pc.setLocalDescription(SimpleSdpObserver(), desc)
                ws?.send(buildJsonObject {
                    put("type", "offer")
                    put("sdp", desc.description)
                }.toString())
            }
        }, MediaConstraints())
    }

    private fun handleSignal(text: String) {
        val obj = runCatching { json.decodeFromString(JsonObject.serializer(), text) }.getOrNull()
            ?: return
        when (obj["type"]?.jsonPrimitive?.content) {
            "answer" -> {
                val sdp = obj["sdp"]?.jsonPrimitive?.content ?: return
                peerConnection?.setRemoteDescription(
                    SimpleSdpObserver(),
                    SessionDescription(SessionDescription.Type.ANSWER, sdp),
                )
            }
            "offer" -> {
                val sdp = obj["sdp"]?.jsonPrimitive?.content ?: return
                val pc = peerConnection ?: return
                pc.setRemoteDescription(object : SimpleSdpObserver() {
                    override fun onSetSuccess() = createAnswer()
                }, SessionDescription(SessionDescription.Type.OFFER, sdp))
            }
            "candidate" -> {
                val c = obj["candidate"]?.jsonObject ?: return
                peerConnection?.addIceCandidate(
                    IceCandidate(
                        c["sdpMid"]?.jsonPrimitive?.content,
                        c["sdpMLineIndex"]?.jsonPrimitive?.content?.toIntOrNull() ?: 0,
                        c["candidate"]?.jsonPrimitive?.content,
                    )
                )
            }
        }
    }

    private fun createAnswer() {
        val pc = peerConnection ?: return
        pc.createAnswer(object : SimpleSdpObserver() {
            override fun onCreateSuccess(desc: SessionDescription) {
                pc.setLocalDescription(SimpleSdpObserver(), desc)
                ws?.send(buildJsonObject {
                    put("type", "answer")
                    put("sdp", desc.description)
                }.toString())
            }
        }, MediaConstraints())
    }

    private fun sendCandidate(candidate: IceCandidate) {
        ws?.send(buildJsonObject {
            put("type", "candidate")
            put("candidate", buildJsonObject {
                put("candidate", candidate.sdp)
                put("sdpMid", candidate.sdpMid)
                put("sdpMLineIndex", candidate.sdpMLineIndex)
            })
        }.toString())
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
        localAudioTrack?.setEnabled(next)
        _state.update { it.copy(micEnabled = next) }
        return next
    }

    override fun toggleCamera(): Boolean {
        val next = !_state.value.cameraEnabled
        localVideoTrack?.setEnabled(next)
        _state.update { it.copy(cameraEnabled = next) }
        return next
    }

    override fun flipCamera() {
        (videoCapturer as? CameraVideoCapturer)?.switchCamera(null)
        _state.update { it.copy(usingFrontCamera = !it.usingFrontCamera) }
    }

    override fun localVideoTrack(): VideoTrack? = localVideoTrack
    override fun remoteVideoTrack(): VideoTrack? = remoteVideoTrack

    override fun end() {
        ticker?.cancel()
        runCatching { videoCapturer?.stopCapture() }
        videoCapturer?.dispose()
        videoSource?.dispose()
        surfaceHelper?.dispose()
        peerConnection?.close()
        peerConnection = null
        ws?.close(1000, "ended")
        ws = null
        _state.update { it.copy(connection = CallConnectionState.Ended) }
    }
}

/** Convenience SdpObserver with empty defaults. */
private open class SimpleSdpObserver : SdpObserver {
    override fun onCreateSuccess(desc: SessionDescription) {}
    override fun onSetSuccess() {}
    override fun onCreateFailure(error: String?) {}
    override fun onSetFailure(error: String?) {}
}
