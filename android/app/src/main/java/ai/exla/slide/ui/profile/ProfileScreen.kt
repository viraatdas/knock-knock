package ai.exla.slide.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.ui.components.AvatarCircle
import ai.exla.slide.ui.components.Hairline
import ai.exla.slide.ui.components.quietClickable
import ai.exla.slide.ui.theme.SlideColors

@Composable
fun ProfileScreen(vm: ProfileViewModel, onLoggedOut: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().height(64.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Profile", style = MaterialTheme.typography.titleLarge, color = SlideColors.Ink)
        }

        // Identity block — large avatar, name, phone.
        Column(
            modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AvatarCircle(name = state.name.ifBlank { state.phone }, size = 96.dp)
            Spacer(Modifier.height(16.dp))

            if (state.editing) {
                TextField(
                    value = state.draftName,
                    onValueChange = vm::setDraftName,
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(
                        color = SlideColors.Ink,
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Light,
                    ),
                    keyboardOptions = KeyboardOptions.Default,
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        cursorColor = SlideColors.Ink,
                        focusedIndicatorColor = SlideColors.Hairline,
                        unfocusedIndicatorColor = SlideColors.Hairline,
                    ),
                )
                Spacer(Modifier.height(12.dp))
                Row {
                    Text(
                        "Cancel",
                        color = SlideColors.InkSecondary,
                        modifier = Modifier.quietClickable { vm.cancelEdit() }.padding(8.dp),
                    )
                    Spacer(Modifier.height(0.dp))
                    Text(
                        "Save",
                        color = SlideColors.Ink,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.quietClickable { vm.saveName() }.padding(8.dp),
                    )
                }
            } else {
                Text(
                    state.name.ifBlank { "Add your name" },
                    color = SlideColors.Ink,
                    fontWeight = FontWeight.Light,
                    fontSize = 26.sp,
                    modifier = Modifier.quietClickable { vm.startEdit() },
                )
                Spacer(Modifier.height(6.dp))
                Text(state.phone, color = SlideColors.InkSecondary, fontSize = 15.sp)
            }
        }

        Spacer(Modifier.height(16.dp))
        Hairline()

        SettingsRow(Icons.Outlined.Notifications, "Notifications") {}
        Hairline(startInset = 52.dp)
        SettingsRow(Icons.Outlined.Lock, "Privacy") {}
        Hairline(startInset = 52.dp)
        SettingsRow(Icons.Outlined.Info, "About") {}
        Hairline()

        Spacer(Modifier.height(24.dp))
        // Log out — subtle red, destructive.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .quietClickable { vm.logout(onLoggedOut) },
            contentAlignment = Alignment.Center,
        ) {
            Text("Log out", color = SlideColors.Danger, style = MaterialTheme.typography.bodyLarge)
        }
        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun SettingsRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().height(56.dp).quietClickable(onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = SlideColors.Ink, modifier = Modifier.height(22.dp))
        Spacer(Modifier.height(0.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            color = SlideColors.Ink,
            modifier = Modifier.padding(start = 16.dp),
        )
    }
}
