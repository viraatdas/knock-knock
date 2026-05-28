package ai.exla.slide

import android.app.Application
import ai.exla.slide.call.telecom.TelecomManagerHelper

class SlideApp : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // Register the self-managed phone account so Slide calls can ring
        // through the OS Telecom framework.
        runCatching { TelecomManagerHelper.registerPhoneAccount(this) }
    }
}
