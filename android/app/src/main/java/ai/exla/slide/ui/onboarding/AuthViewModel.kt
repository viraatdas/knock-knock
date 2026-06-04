package ai.exla.slide.ui.onboarding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.data.repo.SlideRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Step machine for the phone-only onboarding flow. */
enum class AuthStep { Welcome, Phone, Code, Name, Done }

data class AuthState(
    val step: AuthStep = AuthStep.Welcome,
    val countryCode: String = "+1",
    val phoneDigits: String = "",
    val code: String = "",
    val name: String = "",
    val loading: Boolean = false,
    val error: String? = null,
    val resendInSec: Int = 0,
    val isNewUser: Boolean = false,
) {
    val e164: String get() = countryCode + phoneDigits.filter { it.isDigit() }
    val phoneValid: Boolean get() = phoneDigits.filter { it.isDigit() }.length in 7..15
    val codeComplete: Boolean get() = code.length == 6
    val nameValid: Boolean get() = name.trim().length >= 2
}

class AuthViewModel(private val repo: SlideRepository) : ViewModel() {

    private val _state = MutableStateFlow(AuthState())
    val state: StateFlow<AuthState> = _state.asStateFlow()

    fun goToPhone() = _state.update { it.copy(step = AuthStep.Phone, error = null) }

    fun setCountryCode(value: String) =
        _state.update { it.copy(countryCode = value.filter { c -> c == '+' || c.isDigit() }) }

    fun setPhone(value: String) =
        _state.update { it.copy(phoneDigits = value.filter { c -> c.isDigit() }, error = null) }

    fun setCode(value: String) =
        _state.update { it.copy(code = value.filter { c -> c.isDigit() }.take(6), error = null) }

    fun setName(value: String) = _state.update { it.copy(name = value, error = null) }

    fun requestOtp() {
        val s = _state.value
        if (!s.phoneValid || s.loading) return
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            repo.requestOtp(s.e164)
                .onSuccess {
                    _state.update { st -> st.copy(loading = false, step = AuthStep.Code) }
                    startResendCountdown(60)
                }
                .onFailure {
                    _state.update { st ->
                        st.copy(loading = false, error = "Couldn't send the code. Try again.")
                    }
                }
        }
    }

    fun resend() {
        if (_state.value.resendInSec > 0) return
        requestOtp()
    }

    private fun startResendCountdown(seconds: Int) {
        _state.update { it.copy(resendInSec = seconds) }
        viewModelScope.launch {
            var remaining = seconds
            while (remaining > 0) {
                delay(1000)
                remaining--
                _state.update { it.copy(resendInSec = remaining) }
            }
        }
    }

    /** Auto-submits when 6 digits are entered. */
    fun verifyOtp(onAuthenticated: (isNewUser: Boolean) -> Unit) {
        val s = _state.value
        if (!s.codeComplete || s.loading) return
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            repo.verifyOtp(s.e164, s.code)
                .onSuccess { isNew ->
                    // FCM token registration happens once we reach the main
                    // surface (see SlideAppRoot), where the real token is known.
                    if (isNew) {
                        _state.update { it.copy(loading = false, step = AuthStep.Name, isNewUser = true) }
                    } else {
                        _state.update { it.copy(loading = false, step = AuthStep.Done) }
                        onAuthenticated(false)
                    }
                }
                .onFailure {
                    _state.update {
                        it.copy(loading = false, code = "", error = "That code didn't work. Try again.")
                    }
                }
        }
    }

    fun saveName(onDone: () -> Unit) {
        val s = _state.value
        if (!s.nameValid || s.loading) return
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            repo.updateName(s.name.trim())
                .onSuccess {
                    _state.update { it.copy(loading = false, step = AuthStep.Done) }
                    onDone()
                }
                .onFailure {
                    _state.update { it.copy(loading = false, error = "Couldn't save your name. Try again.") }
                }
        }
    }
}
