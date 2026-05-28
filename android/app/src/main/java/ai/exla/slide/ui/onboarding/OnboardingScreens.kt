package ai.exla.slide.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import ai.exla.slide.ui.components.Hairline
import ai.exla.slide.ui.components.PrimaryButton
import ai.exla.slide.ui.components.quietClickable
import ai.exla.slide.ui.theme.SlideColors

/* ---------------- Welcome ---------------- */

@Composable
fun WelcomeScreen(onGetStarted: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .systemBarsPadding()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Text(
            text = "Slide",
            style = MaterialTheme.typography.displayLarge,
            color = SlideColors.Ink,
            fontWeight = FontWeight.Light,
            letterSpacing = 1.8.sp,   // wordmark tracking +0.04em
            fontSize = 44.sp,
        )
        Spacer(Modifier.height(12.dp))
        Text(
            text = "Calls, quietly.",
            style = MaterialTheme.typography.bodyLarge,
            color = SlideColors.InkSecondary,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.weight(1f))
        PrimaryButton(text = "Get started", onClick = onGetStarted)
        Spacer(Modifier.height(40.dp))
    }
}

/* ---------------- Enter phone ---------------- */

@Composable
fun PhoneScreen(vm: AuthViewModel) {
    val state by vm.state.collectAsStateWithLifecycle()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .systemBarsPadding()
            .imePadding()
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Text("Your phone number", style = MaterialTheme.typography.titleLarge, color = SlideColors.Ink)
        Spacer(Modifier.height(8.dp))
        Text(
            "We'll text you a code to confirm it's you.",
            style = MaterialTheme.typography.bodyMedium,
            color = SlideColors.InkSecondary,
        )
        Spacer(Modifier.height(40.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            UnderlineField(
                value = state.countryCode,
                onValueChange = vm::setCountryCode,
                modifier = Modifier.width(72.dp),
                keyboardType = KeyboardType.Phone,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.width(12.dp))
            UnderlineField(
                value = state.phoneDigits,
                onValueChange = vm::setPhone,
                modifier = Modifier.weight(1f).focusRequester(focus),
                keyboardType = KeyboardType.Phone,
                placeholder = "Phone number",
            )
        }

        state.error?.let { ErrorText(it) }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = "Continue",
            onClick = vm::requestOtp,
            enabled = state.phoneValid,
            loading = state.loading,
        )
        Spacer(Modifier.height(24.dp))
    }
}

/* ---------------- Enter code ---------------- */

@Composable
fun CodeScreen(vm: AuthViewModel, onAuthenticated: (Boolean) -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    // Auto-submit when the 6th digit lands.
    LaunchedEffect(state.code) {
        if (state.code.length == 6 && !state.loading) vm.verifyOtp(onAuthenticated)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .systemBarsPadding()
            .imePadding()
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Text("Enter the code", style = MaterialTheme.typography.titleLarge, color = SlideColors.Ink)
        Spacer(Modifier.height(8.dp))
        Text(
            "Sent to ${state.e164}",
            style = MaterialTheme.typography.bodyMedium,
            color = SlideColors.InkSecondary,
        )
        Spacer(Modifier.height(40.dp))

        OtpBoxes(code = state.code, onChange = vm::setCode, focusRequester = focus)

        state.error?.let { ErrorText(it) }

        Spacer(Modifier.height(24.dp))
        if (state.resendInSec > 0) {
            Text(
                "Resend in ${state.resendInSec}s",
                style = MaterialTheme.typography.bodyMedium,
                color = SlideColors.InkSecondary,
            )
        } else {
            Text(
                "Resend code",
                style = MaterialTheme.typography.bodyMedium,
                color = SlideColors.Ink,
                modifier = Modifier.quietClickable { vm.resend() },
            )
        }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = "Continue",
            onClick = { vm.verifyOtp(onAuthenticated) },
            enabled = state.codeComplete,
            loading = state.loading,
        )
        Spacer(Modifier.height(24.dp))
    }
}

/* ---------------- Your name ---------------- */

@Composable
fun NameScreen(vm: AuthViewModel, onDone: () -> Unit) {
    val state by vm.state.collectAsStateWithLifecycle()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(SlideColors.Bg)
            .systemBarsPadding()
            .imePadding()
            .padding(horizontal = 20.dp),
    ) {
        Spacer(Modifier.height(48.dp))
        Text("What's your name?", style = MaterialTheme.typography.titleLarge, color = SlideColors.Ink)
        Spacer(Modifier.height(8.dp))
        Text(
            "This is how friends will see you.",
            style = MaterialTheme.typography.bodyMedium,
            color = SlideColors.InkSecondary,
        )
        Spacer(Modifier.height(40.dp))

        UnderlineField(
            value = state.name,
            onValueChange = vm::setName,
            modifier = Modifier.fillMaxWidth().focusRequester(focus),
            keyboardType = KeyboardType.Text,
            placeholder = "Name",
        )

        state.error?.let { ErrorText(it) }

        Spacer(Modifier.weight(1f))
        PrimaryButton(
            text = "Continue",
            onClick = { vm.saveName(onDone) },
            enabled = state.nameValid,
            loading = state.loading,
        )
        Spacer(Modifier.height(24.dp))
    }
}

/* ---------------- Shared pieces ---------------- */

/** Underline-only text field per DESIGN.md (no box, 1px hairline). */
@Composable
private fun UnderlineField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    keyboardType: KeyboardType = KeyboardType.Text,
    placeholder: String? = null,
    textAlign: TextAlign = TextAlign.Start,
) {
    Column(modifier = modifier) {
        TextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            textStyle = LocalTextStyle.current.copy(
                color = SlideColors.Ink,
                fontSize = 20.sp,
                textAlign = textAlign,
            ),
            placeholder = placeholder?.let {
                {
                    Text(
                        it,
                        color = SlideColors.InkSecondary,
                        fontSize = 20.sp,
                        textAlign = textAlign,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                cursorColor = SlideColors.Ink,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
        )
        Hairline()
    }
}

/** 6 quiet boxes with auto-advance, fed by a single hidden field. */
@Composable
private fun OtpBoxes(code: String, onChange: (String) -> Unit, focusRequester: FocusRequester) {
    Box {
        TextField(
            value = code,
            onValueChange = { onChange(it.take(6)) },
            modifier = Modifier.size(1.dp).focusRequester(focusRequester),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                cursorColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
            ),
        )
        Row(
            modifier = Modifier.fillMaxWidth().quietClickable { focusRequester.requestFocus() },
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            repeat(6) { i ->
                val ch = code.getOrNull(i)?.toString() ?: ""
                val focused = i == code.length
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(56.dp)
                        .background(SlideColors.SurfaceMuted, RoundedCornerShape(12.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(ch, color = SlideColors.Ink, fontSize = 22.sp, fontWeight = FontWeight.Normal)
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(horizontal = 10.dp)
                            .fillMaxWidth()
                            .height(if (focused) 2.dp else 1.dp)
                            .background(if (focused) SlideColors.Ink else SlideColors.Hairline)
                    )
                }
            }
        }
    }
}

@Composable
private fun ErrorText(text: String) {
    Spacer(Modifier.height(12.dp))
    Text(text, style = MaterialTheme.typography.bodyMedium, color = SlideColors.Danger)
}
