package ai.exla.slide.signaling

import ai.exla.slide.data.auth.TokenStore
import ai.exla.slide.data.model.SignalEnvelope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow

/**
 * App-level signaling socket (plane A): GET /v1/ws?token=<accessToken>.
 * Surfaces incoming_call / call_* / participant_* / presence_update events,
 * sends heartbeat/presence_ping, and reconnects with capped exponential backoff.
 * WebRTC SDP/ICE happens with the SFU (plane B), not here.
 */
class SignalingClient(
    private val tokenStore: TokenStore,
    private val wsBaseUrl: String,
    private val json: Json,
) {
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _events = MutableSharedFlow<SignalEnvelope>(extraBufferCapacity = 32)
    val events: SharedFlow<SignalEnvelope> = _events.asSharedFlow()

    private val _connected = MutableSharedFlow<Boolean>(replay = 1, extraBufferCapacity = 4)
    val connected: SharedFlow<Boolean> = _connected.asSharedFlow()

    private var webSocket: WebSocket? = null
    private var loopJob: Job? = null
    private var heartbeatJob: Job? = null
    private var attempt = 0
    @Volatile private var running = false

    fun connect() {
        if (running) return
        running = true
        loopJob = scope.launch { connectLoop() }
    }

    fun disconnect() {
        running = false
        heartbeatJob?.cancel()
        loopJob?.cancel()
        webSocket?.close(1000, "client disconnect")
        webSocket = null
    }

    fun send(envelope: SignalEnvelope): Boolean {
        val payload = json.encodeToString(SignalEnvelope.serializer(), envelope)
        return webSocket?.send(payload) ?: false
    }

    private suspend fun connectLoop() {
        while (running) {
            val token = tokenStore.accessToken
            if (token.isNullOrEmpty()) {
                delay(2000)
                continue
            }
            val url = "${wsBaseUrl.trimEnd('/')}?token=$token"
            val request = Request.Builder().url(url).build()
            val opened = openSocket(request)
            if (!running) break
            attempt = if (opened) 0 else attempt + 1
            val backoffMs = min(30_000.0, 500.0 * 2.0.pow(attempt.toDouble())).toLong()
            delay(backoffMs)
        }
    }

    /** Returns true once the socket successfully opened (so backoff can reset). */
    private suspend fun openSocket(request: Request): Boolean {
        var everOpened = false
        val closed = CompletableDeferred<Unit>()

        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                everOpened = true
                this@SignalingClient.webSocket = webSocket
                _connected.tryEmit(true)
                startHeartbeat()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { json.decodeFromString(SignalEnvelope.serializer(), text) }
                    .onSuccess { _events.tryEmit(it) }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                _connected.tryEmit(false)
                if (!closed.isCompleted) closed.complete(Unit)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                _connected.tryEmit(false)
                if (!closed.isCompleted) closed.complete(Unit)
            }
        }

        client.newWebSocket(request, listener)
        closed.await()
        heartbeatJob?.cancel()
        webSocket = null
        return everOpened
    }

    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (running) {
                delay(25_000)
                send(SignalEnvelope(type = "heartbeat"))
            }
        }
    }
}
