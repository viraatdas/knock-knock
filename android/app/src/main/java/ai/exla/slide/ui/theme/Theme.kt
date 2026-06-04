package ai.exla.slide.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * Slide is intentionally light-only — pure white surfaces are core to the
 * "quiet & precise" identity. The AGENTS.md tokens are mapped onto a Material3
 * color scheme so stock M3 components inherit the right palette.
 */
private val SlideColorScheme = lightColorScheme(
    primary = SlideColors.Accent,
    onPrimary = SlideColors.Bg,
    secondary = SlideColors.InkSecondary,
    onSecondary = SlideColors.Bg,
    background = SlideColors.Bg,
    onBackground = SlideColors.Ink,
    surface = SlideColors.Bg,
    onSurface = SlideColors.Ink,
    surfaceVariant = SlideColors.SurfaceMuted,
    onSurfaceVariant = SlideColors.InkSecondary,
    outline = SlideColors.Hairline,
    outlineVariant = SlideColors.Hairline,
    error = SlideColors.Danger,
    onError = SlideColors.Bg,
)

@Composable
fun SlideTheme(
    @Suppress("UNUSED_PARAMETER") darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = true
            controller.isAppearanceLightNavigationBars = true
        }
    }

    MaterialTheme(
        colorScheme = SlideColorScheme,
        typography = SlideTypography,
        shapes = SlideShapes,
        content = content,
    )
}
