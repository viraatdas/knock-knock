package ai.exla.slide.data.api

import ai.exla.slide.BuildConfig
import ai.exla.slide.data.auth.AuthInterceptor
import ai.exla.slide.data.auth.TokenAuthenticator
import ai.exla.slide.data.auth.TokenStore
import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

/**
 * Builds the configured Retrofit-backed [SlideApi]. Base URL is configurable
 * (defaults to BuildConfig.API_BASE_URL = http://10.0.2.2:8080/v1 for the
 * emulator → host).
 */
class ApiClient(
    private val tokenStore: TokenStore,
    private val baseUrl: String = BuildConfig.API_BASE_URL,
) {
    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        isLenient = true
    }

    private val okHttp: OkHttpClient by lazy {
        val logging = HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BODY
            else HttpLoggingInterceptor.Level.NONE
        }
        OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor(tokenStore))
            .addInterceptor(logging)
            .authenticator(TokenAuthenticator(tokenStore, baseUrl, json))
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    val api: SlideApi by lazy {
        val normalized = if (baseUrl.endsWith("/")) baseUrl else "$baseUrl/"
        Retrofit.Builder()
            .baseUrl(normalized)
            .client(okHttp)
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
            .create(SlideApi::class.java)
    }
}
