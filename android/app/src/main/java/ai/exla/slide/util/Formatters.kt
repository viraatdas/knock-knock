package ai.exla.slide.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Call timer mm:ss (or h:mm:ss past an hour). */
fun formatDuration(totalSec: Int): String {
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%d:%02d", m, s)
}

/**
 * Quiet relative time for the recents list: "Just now", "12m", "3h",
 * "Yesterday", "3d", or a short date. Sentence case (DESIGN.md voice).
 */
fun relativeTime(isoUtc: String?): String {
    val parsed = isoUtc?.let { parseIso(it) } ?: return ""
    val diff = System.currentTimeMillis() - parsed.time
    val mins = diff / 60_000
    val hours = diff / 3_600_000
    val days = diff / 86_400_000
    return when {
        mins < 1 -> "Just now"
        mins < 60 -> "${mins}m"
        hours < 24 -> "${hours}h"
        days < 2 -> "Yesterday"
        days < 7 -> "${days}d"
        else -> SimpleDateFormat("MMM d", Locale.US).format(parsed)
    }
}

private fun parseIso(iso: String): Date? = runCatching {
    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.parse(iso)
}.getOrNull()
