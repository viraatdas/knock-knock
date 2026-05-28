package ai.exla.slide

import android.content.Context
import ai.exla.slide.call.CallService
import ai.exla.slide.call.MockCallService
import ai.exla.slide.data.api.ApiClient
import ai.exla.slide.data.auth.TokenStore
import ai.exla.slide.data.repo.SlideRepository
import ai.exla.slide.signaling.SignalingClient

/**
 * Tiny manual DI container — avoids a heavyweight DI framework for a small
 * graph. Everything is constructed lazily and shared app-wide.
 */
class AppContainer(context: Context) {

    private val appContext = context.applicationContext

    val tokenStore: TokenStore by lazy { TokenStore(appContext) }

    private val apiClient: ApiClient by lazy { ApiClient(tokenStore) }

    val repository: SlideRepository by lazy {
        SlideRepository(apiClient.api, tokenStore, BuildConfig.VERSION_NAME)
    }

    val signalingClient: SignalingClient by lazy {
        SignalingClient(tokenStore, BuildConfig.WS_BASE_URL, apiClient.json)
    }

    /**
     * Default to the mock so the in-call UI renders without a device/SFU. Swap
     * to WebRtcCallService(appContext) for real media on a device.
     */
    val callService: CallService by lazy { MockCallService() }
}
