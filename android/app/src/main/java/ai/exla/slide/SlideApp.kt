package ai.exla.slide

import android.app.Application
import ai.exla.slide.call.telecom.TelecomManagerHelper
import ai.exla.slide.messaging.IncomingCallNotifier

class SlideApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // Register the self-managed phone account so Slide calls can ring
        // through the OS Telecom framework.
        runCatching { TelecomManagerHelper.registerPhoneAccount(this) }
        // Create the high-importance incoming-call channel up front so push
        // notifications ring full-screen. Safe to call without Firebase.
        runCatching { IncomingCallNotifier.ensureChannel(this) }
    }
}
