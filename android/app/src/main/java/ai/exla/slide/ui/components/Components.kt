package ai.exla.slide.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.exla.slide.ui.theme.SlideColors

/**
 * Primary button — pure-black fill, white text, height 52, radius 14, no shadow.
 * Press: 96% scale + slight opacity (≈150ms). (DESIGN.md)
 */
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, label = "primaryScale")
    val active = enabled && !loading

    Surface(
        onClick = { if (active) onClick() },
        enabled = active,
        interactionSource = interaction,
        shape = MaterialTheme.shapes.medium,
        color = if (active) SlideColors.Accent else SlideColors.Hairline,
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .scale(scale)
            .alpha(if (pressed) 0.92f else 1f),
    ) {
        Box(contentAlignment = Alignment.Center) {
            if (loading) {
                CircularProgressIndicator(
                    color = SlideColors.Bg,
                    strokeWidth = 1.5.dp,
                    modifier = Modifier.size(20.dp),
                )
            } else {
                Text(
                    text = text,
                    style = MaterialTheme.typography.labelLarge,
                    color = if (active) SlideColors.Bg else SlideColors.InkSecondary,
                )
            }
        }
    }
}

/** Secondary button — white fill, 1px hairline border, ink text. */
@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, label = "secondaryScale")

    Surface(
        onClick = onClick,
        enabled = enabled,
        interactionSource = interaction,
        shape = MaterialTheme.shapes.medium,
        color = SlideColors.Bg,
        border = BorderStroke(1.dp, SlideColors.Hairline),
        modifier = modifier
            .fillMaxWidth()
            .height(52.dp)
            .scale(scale),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelLarge,
                color = SlideColors.Ink,
            )
        }
    }
}

/** Hairline divider — 1px, optionally inset to align past an avatar. */
@Composable
fun Hairline(
    modifier: Modifier = Modifier,
    startInset: Dp = 0.dp,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = startInset)
            .height(1.dp)
            .background(SlideColors.Hairline)
    )
}

/**
 * Avatar circle — initials in ink on a muted fill (image support could layer on
 * top later via Coil). Sizes: 40 (list), 64 (sheet), 96+ (call/profile).
 */
@Composable
fun AvatarCircle(
    name: String?,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    backgroundColor: Color = SlideColors.SurfaceMuted,
    textColor: Color = SlideColors.Ink,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(backgroundColor),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initialsOf(name),
            color = textColor,
            fontWeight = FontWeight.Light,
            fontSize = (size.value * 0.36f).sp,
        )
    }
}

fun initialsOf(name: String?): String {
    val parts = name?.trim()?.split(Regex("\\s+"))?.filter { it.isNotEmpty() } ?: emptyList()
    return when {
        parts.isEmpty() -> "?"
        parts.size == 1 -> parts[0].take(1).uppercase()
        else -> (parts.first().take(1) + parts.last().take(1)).uppercase()
    }
}

/**
 * Thin circular icon button — outlined (1.5px) by default, or filled (for
 * end-call in danger). Icon centered. (DESIGN.md)
 */
@Composable
fun CircleIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    diameter: Dp = 64.dp,
    filled: Boolean = false,
    color: Color = SlideColors.Ink,
    iconTint: Color? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.94f else 1f, label = "circleScale")

    Surface(
        onClick = onClick,
        interactionSource = interaction,
        shape = CircleShape,
        color = if (filled) color else Color.Transparent,
        border = if (filled) null else BorderStroke(1.5.dp, color),
        modifier = modifier.size(diameter).scale(scale),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = iconTint ?: if (filled) SlideColors.Bg else color,
                modifier = Modifier.size(diameter * 0.42f),
            )
        }
    }
}

@Composable
fun WSpacer(width: Dp) = Spacer(Modifier.width(width))

/** Centered, quiet empty state. */
@Composable
fun EmptyState(text: String, modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = SlideColors.InkSecondary,
            textAlign = TextAlign.Center,
        )
    }
}
