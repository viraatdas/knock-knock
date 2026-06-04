package ai.exla.slide.ui.contacts

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.call.CallPeer
import ai.exla.slide.data.model.Contact
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.CircleIconButton
import ai.exla.slide.ui.components.EmptyState
import ai.exla.slide.ui.components.Hairline
import ai.exla.slide.ui.components.PrimaryButton
import ai.exla.slide.ui.components.quietClickable
import ai.exla.slide.ui.theme.SlideColors

@Composable
fun ContactsScreen(
    vm: ContactsViewModel,
    onCall: (CallPeer) -> Unit,
    onKnock: (CallPeer) -> Unit,
) {
    val state by vm.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var sheetContact by remember { mutableStateOf<Contact?>(null) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            vm.sync(readDevicePhoneNumbers(context))
        } else {
            vm.setImporting(false)
        }
    }

    val importContacts: () -> Unit = {
        vm.setImporting(true)
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS)
            == PackageManager.PERMISSION_GRANTED
        ) {
            vm.sync(readDevicePhoneNumbers(context))
        } else {
            permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
        }
    }

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
            Spacer(Modifier.weight(1f))
            // Header import action.
            IconButton(onClick = importContacts, enabled = !state.importing) {
                Icon(
                    Icons.Outlined.FileDownload,
                    contentDescription = "Import contacts",
                    tint = SlideColors.Ink,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        // Pinned search field.
        SearchField(value = state.query, onValueChange = vm::setQuery)
        Spacer(Modifier.height(12.dp))
        DirectDialPanel(
            number = state.dialNumber,
            onNumberChange = vm::setDialNumber,
            checking = state.dialChecking,
            match = state.dialLookup,
            message = state.dialMessage,
            onCheck = vm::checkDialNumber,
            onInvite = { invite(context, state.dialNumber) },
            onAudio = { state.dialLookup?.toPeer()?.let(onCall) },
            onVideo = { state.dialLookup?.toPeer()?.let(onCall) },
            onKnock = { state.dialLookup?.toPeer()?.let(onKnock) },
        )
        Spacer(Modifier.height(8.dp))

        val groups = state.grouped
        when {
            state.loading && state.all.isEmpty() -> EmptyState("", Modifier.fillMaxSize())
            groups.isEmpty() -> Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "No contacts yet",
                    style = MaterialTheme.typography.bodyLarge,
                    color = SlideColors.InkSecondary,
                )
                Spacer(Modifier.height(24.dp))
                PrimaryButton(
                    text = "Import contacts",
                    onClick = importContacts,
                    loading = state.importing,
                    modifier = Modifier.padding(horizontal = 40.dp),
                )
            }
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
                                onInvite = { invite(context, contact.phone) },
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
            onKnock = {
                sheetContact = null
                onKnock(contact.toPeer())
            },
        )
    }
}

/** Reads name + phone numbers from the device address book. Caller must hold READ_CONTACTS. */
private fun readDevicePhoneNumbers(context: Context): List<String> {
    val phones = mutableListOf<String>()
    val resolver = context.contentResolver
    val projection = arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER)
    runCatching {
        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            projection, null, null, null,
        )?.use { cursor ->
            val numberIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (cursor.moveToNext() && phones.size < 1000) {
                if (numberIdx >= 0) cursor.getString(numberIdx)?.let { phones.add(it) }
            }
        }
    }
    return phones
}

/** Fires an SMS intent pre-filled with the verbatim invite, with a chooser fallback. */
private fun invite(context: Context, phone: String) {
    val sms = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
        putExtra("sms_body", InviteMessage.BODY)
    }
    runCatching { context.startActivity(sms) }.onFailure {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, InviteMessage.BODY)
        }
        runCatching { context.startActivity(Intent.createChooser(send, "Invite to Slide")) }
    }
}

@Composable
private fun DirectDialPanel(
    number: String,
    onNumberChange: (String) -> Unit,
    checking: Boolean,
    match: Contact?,
    message: String?,
    onCheck: () -> Unit,
    onInvite: () -> Unit,
    onAudio: () -> Unit,
    onVideo: () -> Unit,
    onKnock: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(SlideColors.SurfaceMuted, RoundedCornerShape(16.dp))
            .padding(14.dp),
    ) {
        Text("Call by phone number", style = MaterialTheme.typography.labelLarge, color = SlideColors.Ink)
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextField(
                value = number,
                onValueChange = onNumberChange,
                modifier = Modifier.weight(1f),
                singleLine = true,
                placeholder = { Text("+1 415 555 0123", color = SlideColors.InkSecondary) },
                textStyle = MaterialTheme.typography.bodyLarge,
                shape = RoundedCornerShape(12.dp),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = SlideColors.Bg,
                    unfocusedContainerColor = SlideColors.Bg,
                    cursorColor = SlideColors.Ink,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    focusedTextColor = SlideColors.Ink,
                    unfocusedTextColor = SlideColors.Ink,
                ),
            )
            Spacer(Modifier.width(10.dp))
            val canCheck = number.filter { it.isDigit() }.length >= 4 && !checking
            Box(
                modifier = Modifier
                    .width(104.dp)
                    .height(52.dp)
                    .background(
                        if (canCheck) SlideColors.Ink else SlideColors.Hairline,
                        RoundedCornerShape(14.dp),
                    )
                    .quietClickable { if (canCheck) onCheck() },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (checking) "Checking" else "Check",
                    color = if (canCheck) SlideColors.Bg else SlideColors.InkSecondary,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }

        when {
            match != null -> {
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    AvatarCircle(name = match.displayName ?: match.phone, size = 36.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(match.displayName ?: match.phone, color = SlideColors.Ink)
                        Text("On Slide", color = SlideColors.InkSecondary, fontSize = 13.sp)
                    }
                    KnockCircleButton(onClick = onKnock, diameter = 42.dp)
                    Spacer(Modifier.width(8.dp))
                    CircleIconButton(Icons.Outlined.Phone, "Audio call", onAudio, diameter = 42.dp)
                    Spacer(Modifier.width(8.dp))
                    CircleIconButton(Icons.Outlined.Videocam, "Video call", onVideo, diameter = 42.dp)
                }
            }
            message != null -> {
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(message, color = SlideColors.InkSecondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
                    Text(
                        "Invite",
                        color = SlideColors.Ink,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.quietClickable(onInvite),
                    )
                }
            }
        }
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
private fun ContactRow(contact: Contact, onClick: () -> Unit, onInvite: () -> Unit) {
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
                modifier = Modifier.quietClickable(onInvite),
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
    onKnock: () -> Unit,
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
            Row(horizontalArrangement = Arrangement.spacedBy(32.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    KnockCircleButton(onClick = onKnock)
                    Spacer(Modifier.height(8.dp))
                    Text("Knock", style = MaterialTheme.typography.bodySmall, color = SlideColors.InkSecondary)
                }
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

/** Circular ✊ knock button — outlined to match [CircleIconButton]'s ink styling. */
@Composable
private fun KnockCircleButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    diameter: androidx.compose.ui.unit.Dp = 64.dp,
) {
    Box(
        modifier = modifier
            .size(diameter)
            .clip(androidx.compose.foundation.shape.CircleShape)
            .border(
                androidx.compose.foundation.BorderStroke(1.5.dp, SlideColors.Ink),
                androidx.compose.foundation.shape.CircleShape,
            )
            .quietClickable(onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text = "✊", fontSize = (diameter.value * 0.40f).sp)
    }
}

private fun Contact.toPeer() =
    CallPeer(userId = callUserId ?: id ?: phone, displayName = displayName ?: phone, phone = phone)
