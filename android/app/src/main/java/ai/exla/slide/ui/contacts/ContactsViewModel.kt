package ai.exla.slide.ui.contacts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import ai.exla.slide.data.model.Contact
import ai.exla.slide.data.repo.SlideRepository
import kotlinx.coroutines.Job
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
    val dialNumber: String = "",
    val dialLookup: Contact? = null,
    val dialChecking: Boolean = false,
    val dialMessage: String? = null,
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
    private var loadJob: Job? = null

    init { load() }

    fun setQuery(value: String) = _state.update { it.copy(query = value) }

    fun setDialNumber(value: String) =
        _state.update {
            it.copy(
                dialNumber = value,
                dialLookup = null,
                dialMessage = null,
            )
        }

    fun load(silent: Boolean = false, force: Boolean = false) {
        val existing = loadJob
        if (existing?.isActive == true) {
            if (!force) return
            existing.cancel()
        }
        if (!silent) {
            _state.update { it.copy(loading = true, error = null) }
        }
        loadJob = viewModelScope.launch {
            repo.getContacts()
                .onSuccess { contacts -> _state.update { it.copy(loading = false, all = contacts) } }
                .onFailure {
                    _state.update {
                        it.copy(
                            loading = false,
                            error = if (silent) it.error else "Couldn't load contacts.",
                        )
                    }
                }
        }
    }

    /** Sync device phone numbers, then reload the matched/known set. */
    fun sync(phones: List<String>, names: List<String> = emptyList()) {
        viewModelScope.launch {
            _state.update { it.copy(importing = true) }
            repo.syncContacts(phones, names)
                .onFailure {
                    _state.update { it.copy(error = "Couldn't import contacts.") }
                }
            _state.update { it.copy(importing = false) }
            load(force = true)
        }
    }

    fun checkDialNumber() {
        val phone = state.value.dialNumber.trim()
        if (phone.filter(Char::isDigit).length < 4) return
        viewModelScope.launch {
            _state.update { it.copy(dialChecking = true, dialLookup = null, dialMessage = null) }
            repo.syncContacts(listOf(phone), listOf(phone))
                .onSuccess { contacts ->
                    val match = contacts.firstOrNull()
                    _state.update {
                        if (match?.onSlide == true && match.callUserId != null) {
                            it.copy(
                                dialChecking = false,
                                dialLookup = match,
                                dialMessage = null,
                            )
                        } else {
                            it.copy(
                                dialChecking = false,
                                dialLookup = null,
                                dialMessage = "That number is not on Slide yet.",
                            )
                        }
                    }
                }
                .onFailure {
                    _state.update {
                        it.copy(
                            dialChecking = false,
                            dialLookup = null,
                            dialMessage = "Couldn't check that number.",
                        )
                    }
                }
        }
    }

    fun setImporting(value: Boolean) = _state.update { it.copy(importing = value) }
}

val Contact.callUserId: String?
    get() = contactUserId ?: userId
