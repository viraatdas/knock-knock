package ai.exla.slide

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import ai.exla.slide.ui.nav.SlideAppRoot
import ai.exla.slide.ui.theme.SlideTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val container = (application as SlideApp).container

        setContent {
            SlideTheme {
                SlideAppRoot(container = container)
            }
        }
    }
}
