package ai.exla.slide.ui.contacts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.data.model.Contact
import ai.exla.slide.data.repo.SlideRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Single source of truth for the SMS invite text. Verbatim — do not reword.
 */
object InviteMessage {
    const val BODY =
        "yo big dog - the hottest video calling app has dropped. drop your shi and download this asap so i can ring you mothereffer" +
            "\n\n" +
            "https://slide.viraat.dev"
}

data class ContactsState(
    val query: String = "",
    val all: List<Contact> = emptyList(),
    val loading: Boolean = true,
    val importing: Boolean = false,
    val error: String? = null,
) {
    /** Filtered + grouped by first letter, sorted alphabetically. */
    val grouped: List<Pair<String, List<Contact>>>
        get() {
            val filtered = if (query.isBlank()) all else all.filter {
                (it.displayName ?: it.phone).contains(query, ignoreCase = true) ||
                    it.phone.contains(query)
            }
            return filtered
                .sortedBy { (it.displayName ?: it.phone).lowercase() }
                .groupBy { sectionLetter(it) }
                .toSortedMap()
                .map { it.key to it.value }
        }

    private fun sectionLetter(c: Contact): String {
        val ch = (c.displayName ?: c.phone).trim().firstOrNull()?.uppercaseChar()
        return if (ch != null && ch.isLetter()) ch.toString() else "#"
    }
}

class ContactsViewModel(private val repo: SlideRepository) : ViewModel() {

    private val _state = MutableStateFlow(ContactsState())
    val state: StateFlow<ContactsState> = _state.asStateFlow()

    init { load() }

    fun setQuery(value: String) = _state.update { it.copy(query = value) }

    fun load() {
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            repo.getContacts()
                .onSuccess { contacts -> _state.update { it.copy(loading = false, all = contacts) } }
                .onFailure { _state.update { it.copy(loading = false, error = "Couldn't load contacts.") } }
        }
    }

    /** Sync device phone numbers, then reload the matched/known set. */
    fun sync(phones: List<String>) {
        viewModelScope.launch {
            _state.update { it.copy(importing = true) }
            repo.syncContacts(phones)
            _state.update { it.copy(importing = false) }
            load()
        }
    }

    fun setImporting(value: Boolean) = _state.update { it.copy(importing = value) }
}
