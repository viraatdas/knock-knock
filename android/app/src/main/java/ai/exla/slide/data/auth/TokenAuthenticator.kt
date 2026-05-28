package ai.exla.slide.data.auth

import ai.exla.slide.data.model.RefreshBody
import ai.exla.slide.data.model.RefreshResponse
import kotlinx.serialization.json.Json
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route

/**
 * Silent refresh on 401: exchanges the refresh token for a new access token via
 * POST /auth/refresh, then retries the original request. Uses a bare
 * OkHttpClient (no auth interceptor) to avoid recursion. If refresh fails,
 * credentials are cleared and the request gives up (caller routes to login).
 */
class TokenAuthenticator(
    private val tokenStore: TokenStore,
    private val baseUrl: String,
    private val json: Json,
) : Authenticator {

    private val refreshClient = OkHttpClient.Builder().build()
    private val lock = Any()

    override fun authenticate(route: Route?, response: Response): Request? {
        if (responseCount(response) >= 2) return null

        val currentAccess = tokenStore.accessToken
        val refresh = tokenStore.refreshToken ?: return null

        synchronized(lock) {
            // Another thread may have already refreshed while we waited.
            val latest = tokenStore.accessToken
            if (latest != null && latest != currentAccess) {
                return response.request.newBuilder()
                    .header("Authorization", "Bearer $latest")
                    .build()
            }

            val newAccess = runCatching { refreshTokens(refresh) }.getOrNull() ?: run {
                tokenStore.clear()
                return null
            }

            return response.request.newBuilder()
                .header("Authorization", "Bearer $newAccess")
                .build()
        }
    }

    private fun refreshTokens(refresh: String): String? {
        val url = "${baseUrl.trimEnd('/')}/auth/refresh"
        val payload = json.encodeToString(RefreshBody.serializer(), RefreshBody(refresh))
        val body = payload.toRequestBody("application/json; charset=utf-8".toMediaType())
        val req = Request.Builder().url(url).post(body).build()

        refreshClient.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) return null
            val raw = resp.body?.string() ?: return null
            val parsed = json.decodeFromString(RefreshResponse.serializer(), raw)
            tokenStore.saveTokens(parsed.accessToken, parsed.refreshToken)
            return parsed.accessToken
        }
    }

    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count++
            prior = prior.priorResponse
        }
        return count
    }
}
