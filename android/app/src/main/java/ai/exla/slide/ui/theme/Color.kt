package ai.exla.slide.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Design tokens from DESIGN.md ("Quiet & Precise").
 * No gradients, no decorative color — one restrained accent (pure black).
 */
object SlideColors {
    val Bg = Color(0xFFFFFFFF)            // every background
    val BgGrouped = Color(0xFFFAFAFA)     // grouped sections
    val Ink = Color(0xFF0A0A0A)           // primary near-black text, line icons
    val InkSecondary = Color(0xFF6B7280)  // secondary gray
    val Hairline = Color(0xFFECECEC)      // 1px borders & dividers
    val Accent = Color(0xFF0A0A0A)        // primary action — pure black
    val Danger = Color(0xFFE5484D)        // end call / decline / log out — the ONLY red
    val SurfaceMuted = Color(0xFFFAFAFA)  // subtle fills (search field, otp boxes)

    // On-video chrome (in-call) uses translucent white over remote video.
    val OnVideo = Color(0xFFFFFFFF)
    val OnVideoScrim = Color(0x33000000)
}
