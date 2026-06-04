package ai.exla.slide.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/** Radii from AGENTS.md: 12–16px, subtle. Buttons 14, cards/sheets 16. */
val SlideShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(14.dp),   // primary buttons
    large = RoundedCornerShape(16.dp),    // cards, sheets
    extraLarge = RoundedCornerShape(24.dp),
)
