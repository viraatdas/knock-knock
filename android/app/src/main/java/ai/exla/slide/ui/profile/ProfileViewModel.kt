package ai.exla.slide.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.data.auth.TokenStore
import ai.exla.slide.data.repo.SlideRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ProfileState(
    val name: String = "",
    val phone: String = "",
    val editing: Boolean = false,
    val draftName: String = "",
    val loading: Boolean = false,
)

class ProfileViewModel(
    private val repo: SlideRepository,
    private val tokenStore: TokenStore,
) : ViewModel() {

    private val _state = MutableStateFlow(
        ProfileState(
            name = tokenStore.displayName ?: "",
            phone = tokenStore.phone ?: "",
        )
    )
    val state: StateFlow<ProfileState> = _state.asStateFlow()

    init { refresh() }

    fun refresh() {
        viewModelScope.launch {
            repo.getMe().onSuccess { user ->
                _state.update {
                    it.copy(name = user.displayName ?: "", phone = user.phone)
                }
            }
        }
    }

    fun startEdit() = _state.update { it.copy(editing = true, draftName = it.name) }
    fun cancelEdit() = _state.update { it.copy(editing = false) }
    fun setDraftName(value: String) = _state.update { it.copy(draftName = value) }

    fun saveName() {
        val draft = _state.value.draftName.trim()
        if (draft.length < 2) return
        _state.update { it.copy(loading = true) }
        viewModelScope.launch {
            repo.updateName(draft)
                .onSuccess { user ->
                    _state.update {
                        it.copy(name = user.displayName ?: draft, editing = false, loading = false)
                    }
                }
                .onFailure { _state.update { it.copy(loading = false, editing = false) } }
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch {
            repo.logout()
            onDone()
        }
    }
}
