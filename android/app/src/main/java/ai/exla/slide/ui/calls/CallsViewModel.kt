package ai.exla.slide.ui.calls

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.data.model.Call
import ai.exla.slide.data.repo.SlideRepository
import ai.exla.slide.signaling.SignalingClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class CallsState(
    val calls: List<Call> = emptyList(),
    val loading: Boolean = true,
    val error: String? = null,
)

class CallsViewModel(
    private val repo: SlideRepository,
    private val signaling: SignalingClient,
) : ViewModel() {

    private val _state = MutableStateFlow(CallsState())
    val state: StateFlow<CallsState> = _state.asStateFlow()

    init {
        refresh()
        observeSignaling()
    }

    fun refresh() {
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            repo.getCalls()
                .onSuccess { calls -> _state.update { it.copy(loading = false, calls = calls) } }
                .onFailure { _state.update { it.copy(loading = false, error = "Couldn't load calls.") } }
        }
    }

    /** Refresh recents whenever a call lifecycle event arrives. */
    private fun observeSignaling() {
        viewModelScope.launch {
            signaling.events.collect { event ->
                when (event.type) {
                    "call_ended", "call_declined", "call_accepted", "incoming_call" -> refresh()
                }
            }
        }
    }
}
