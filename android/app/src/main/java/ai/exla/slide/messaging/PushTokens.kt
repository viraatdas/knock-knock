package ai.exla.slide.messaging

import ai.exla.slide.data.repo.SlideRepository
import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Safe entry point for fetching + registering the FCM push token. Everything is
 * guarded so the app runs without Firebase wired up: if no FirebaseApp has been
 * initialized (i.e. google-services.json + the google-services plugin are not
 * present yet) this is a no-op rather than a crash.
 */
object PushTokens {

    private const val TAG = "PushTokens"

    /** True only when a default FirebaseApp exists (json + plugin present). */
    fun isFirebaseAvailable(context: Context): Boolean =
        runCatching { FirebaseApp.getInstance() }.getOrNull() != null

    /**
     * Fetch the current FCM token and register it with the backend. Call after
     * sign-in. No-ops (without throwing) when Firebase isn't configured yet.
     */
    fun registerCurrentToken(context: Context, repository: SlideRepository) {
        if (!isFirebaseAvailable(context)) {
            Log.i(TAG, "Firebase not configured; skipping FCM token registration")
            return
        }
        val scope = CoroutineScope(Dispatchers.IO)
        runCatching {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                val token = task.result
                if (task.isSuccessful && !token.isNullOrBlank()) {
                    scope.launch { repository.registerDevice(token) }
                } else {
                    Log.w(TAG, "Failed to fetch FCM token", task.exception)
                }
            }
        }.onFailure { Log.w(TAG, "FirebaseMessaging unavailable", it) }
    }
}
