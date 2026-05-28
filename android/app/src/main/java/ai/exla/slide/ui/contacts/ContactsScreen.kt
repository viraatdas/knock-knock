package ai.exla.slide.ui.contacts

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.call.CallPeer
import ai.exla.slide.data.model.Contact
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.CircleIconButton
import ai.exla.slide.ui.components.EmptyState
import ai.exla.slide.ui.components.Hairline
import ai.exla.slide.ui.components.quietClickable
import ai.exla.slide.ui.theme.SlideColors

@Composable
fun ContactsScreen(vm: ContactsViewModel, onCall: (CallPeer) -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    var sheetContact by remember { mutableStateOf<Contact?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .padding(horizontal = 20.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().height(64.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Contacts", style = MaterialTheme.typography.titleLarge, color = SlideColors.Ink)
        }

        // Pinned search field.
        SearchField(value = state.query, onValueChange = vm::setQuery)
        Spacer(Modifier.height(8.dp))

        val groups = state.grouped
        when {
            state.loading && state.all.isEmpty() -> EmptyState("", Modifier.fillMaxSize())
            groups.isEmpty() -> EmptyState("No contacts yet", Modifier.fillMaxSize())
            else -> LazyColumn(Modifier.fillMaxSize()) {
                groups.forEach { (letter, contacts) ->
                    item(key = "header-$letter") { SectionHeader(letter) }
                    contacts.forEach { contact ->
                        item(key = contact.id ?: contact.phone) {
                            ContactRow(
                                contact = contact,
                                onClick = {
                                    if (contact.onSlide) sheetContact = contact
                                },
                            )
                            Hairline(startInset = 56.dp)
                        }
                    }
                }
            }
        }
    }

    sheetContact?.let { contact ->
        ContactSheet(
            contact = contact,
            onDismiss = { sheetContact = null },
            onAudio = {
                sheetContact = null
                onCall(contact.toPeer())
            },
            onVideo = {
                sheetContact = null
                onCall(contact.toPeer())
            },
        )
    }
}

@Composable
private fun SearchField(value: String, onValueChange: (String) -> Unit) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        leadingIcon = {
            Icon(Icons.Outlined.Search, null, tint = SlideColors.InkSecondary, modifier = Modifier.size(20.dp))
        },
        placeholder = { Text("Search", color = SlideColors.InkSecondary) },
        textStyle = MaterialTheme.typography.bodyLarge,
        shape = RoundedCornerShape(12.dp),
        keyboardOptions = KeyboardOptions.Default,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = SlideColors.SurfaceMuted,
            unfocusedContainerColor = SlideColors.SurfaceMuted,
            cursorColor = SlideColors.Ink,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = SlideColors.Ink,
            unfocusedTextColor = SlideColors.Ink,
        ),
    )
}

@Composable
private fun SectionHeader(letter: String) {
    Box(modifier = Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 4.dp)) {
        Text(
            text = letter,
            style = MaterialTheme.typography.labelSmall,
            color = SlideColors.InkSecondary,
            fontWeight = FontWeight.Normal,
        )
    }
}

@Composable
private fun ContactRow(contact: Contact, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().height(64.dp).quietClickable(onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarCircle(name = contact.displayName ?: contact.phone, size = 40.dp)
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(
                contact.displayName ?: contact.phone,
                style = MaterialTheme.typography.bodyLarge,
                color = SlideColors.Ink,
            )
            if (contact.displayName != null) {
                Text(contact.phone, style = MaterialTheme.typography.bodySmall, color = SlideColors.InkSecondary)
            }
        }
        if (!contact.onSlide) {
            Text(
                "Invite",
                style = MaterialTheme.typography.bodyMedium,
                color = SlideColors.InkSecondary,
            )
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun ContactSheet(
    contact: Contact,
    onDismiss: () -> Unit,
    onAudio: () -> Unit,
    onVideo: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SlideColors.Bg,
        dragHandle = null,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AvatarCircle(name = contact.displayName ?: contact.phone, size = 80.dp)
            Spacer(Modifier.height(16.dp))
            Text(
                contact.displayName ?: contact.phone,
                style = MaterialTheme.typography.titleLarge,
                color = SlideColors.Ink,
            )
            Spacer(Modifier.height(4.dp))
            Text(contact.phone, style = MaterialTheme.typography.bodyMedium, color = SlideColors.InkSecondary)
            Spacer(Modifier.height(32.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(40.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircleIconButton(Icons.Outlined.Phone, "Voice call", onAudio)
                    Spacer(Modifier.height(8.dp))
                    Text("Audio", style = MaterialTheme.typography.bodySmall, color = SlideColors.InkSecondary)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircleIconButton(Icons.Outlined.Videocam, "Video call", onVideo)
                    Spacer(Modifier.height(8.dp))
                    Text("Video", style = MaterialTheme.typography.bodySmall, color = SlideColors.InkSecondary)
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

private fun Contact.toPeer() =
    CallPeer(userId = contactUserId ?: id ?: phone, displayName = displayName, phone = phone)
