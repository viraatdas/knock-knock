package ai.exla.slide.data.repo

import ai.exla.slide.data.api.SlideApi
import ai.exla.slide.data.auth.TokenStore
import ai.exla.slide.data.model.Call
import ai.exla.slide.data.model.CallSession
import ai.exla.slide.data.model.Contact
import ai.exla.slide.data.model.CreateCallBody
import ai.exla.slide.data.model.LogoutBody
import ai.exla.slide.data.model.PatchMeBody
import ai.exla.slide.data.model.RegisterDeviceBody
import ai.exla.slide.data.model.RequestOtpBody
import ai.exla.slide.data.model.SyncContactsBody
import ai.exla.slide.data.model.User
import ai.exla.slide.data.model.VerifyOtpBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Coroutine-friendly wrapper over [SlideApi] that also persists auth state.
 * ViewModels depend on this rather than touching Retrofit directly.
 */
class SlideRepository(
    private val api: SlideApi,
    private val tokenStore: TokenStore,
    private val appVersion: String = "1.0.0",
) {
    /* ---- Auth ---- */

    /** Returns the dev OTP code if the backend echoes one (dev only). */
    suspend fun requestOtp(phone: String): Result<String?> = io {
        val resp = api.requestOtp(RequestOtpBody(phone))
        resp.body()?.devCode
    }

    /** Returns isNewUser flag; tokens + identity stored as a side effect. */
    suspend fun verifyOtp(phone: String, code: String): Result<Boolean> = io {
        val resp = api.verifyOtp(VerifyOtpBody(phone, code))
        tokenStore.saveTokens(resp.accessToken, resp.refreshToken)
        tokenStore.userId = resp.user.id
        tokenStore.phone = resp.user.phone
        tokenStore.displayName = resp.user.displayName
        resp.isNewUser
    }

    suspend fun registerDevice(pushToken: String): Result<Unit> = io {
        api.registerDevice(
            RegisterDeviceBody(pushToken = pushToken, platform = "android", appVersion = appVersion)
        )
        Unit
    }

    suspend fun logout(): Result<Unit> = io {
        tokenStore.refreshToken?.takeIf { it.isNotEmpty() }?.let {
            runCatching { api.logout(LogoutBody(it)) }
        }
        tokenStore.clear()
        Unit
    }

    /* ---- Me ---- */

    suspend fun getMe(): Result<User> = io {
        api.getMe().also {
            tokenStore.phone = it.phone
            tokenStore.displayName = it.displayName
        }
    }

    suspend fun updateName(name: String): Result<User> = io {
        api.patchMe(PatchMeBody(displayName = name)).also {
            tokenStore.displayName = it.displayName
        }
    }

    /* ---- Contacts ---- */

    suspend fun syncContacts(phones: List<String>): Result<List<Contact>> = io {
        api.syncContacts(SyncContactsBody(phones))
    }

    suspend fun getContacts(): Result<List<Contact>> = io { api.getContacts() }

    /* ---- Calls ---- */

    suspend fun getCalls(): Result<List<Call>> = io { api.getCalls().calls }

    /** One-to-one call: a single participant user id. */
    suspend fun createCall(peerUserId: String): Result<CallSession> = io {
        api.createCall(CreateCallBody(type = "one_to_one", participantUserIds = listOf(peerUserId)))
    }

    suspend fun acceptCall(callId: String): Result<CallSession> = io { api.acceptCall(callId) }

    suspend fun declineCall(callId: String): Result<Unit> = io { api.declineCall(callId); Unit }

    suspend fun leaveCall(callId: String): Result<Unit> = io { api.leaveCall(callId); Unit }

    private suspend inline fun <T> io(crossinline block: suspend () -> T): Result<T> =
        withContext(Dispatchers.IO) { runCatching { block() } }
}
