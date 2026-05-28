package ai.exla.slide.data.auth

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Adds the bearer access token to every outgoing request, except the auth
 * endpoints that establish or refresh credentials.
 */
class AuthInterceptor(private val tokenStore: TokenStore) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val path = request.url.encodedPath

        val isAuthEndpoint = path.endsWith("/auth/request-otp") ||
            path.endsWith("/auth/verify-otp") ||
            path.endsWith("/auth/refresh")

        val token = tokenStore.accessToken
        if (isAuthEndpoint || token.isNullOrEmpty()) {
            return chain.proceed(request)
        }

        val authed = request.newBuilder()
            .header("Authorization", "Bearer $token")
            .build()
        return chain.proceed(authed)
    }
}
