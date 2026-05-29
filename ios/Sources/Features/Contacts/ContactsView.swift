import SwiftUI
import Contacts

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    @Published var isImporting = false

    private let api = APIClient.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await api.contacts()
            contacts = list.sorted { $0.displayName < $1.displayName }
        } catch {
            if Config.useMockData {
                contacts = MockData.contacts.sorted { $0.displayName < $1.displayName }
            }
        }
    }

    /// User-triggered: request Contacts permission, read names + numbers, sync,
    /// then refresh so on-Slide vs not is reflected.
    func importContacts() async {
        isImporting = true
        defer { isImporting = false }
        await syncDeviceContacts()
        await load()
    }

    private func syncDeviceContacts() async {
        let store = CNContactStore()
        guard CNContactStore.authorizationStatus(for: .contacts) != .denied else { return }
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return }
            let keys = [
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var phones: [String] = []
            try store.enumerateContacts(with: request) { contact, _ in
                for number in contact.phoneNumbers {
                    phones.append(number.value.stringValue)
                }
            }
            if !phones.isEmpty {
                _ = try? await api.syncContacts(phones: Array(phones.prefix(1000)))
            }
        } catch {
            // Ignore; falls back to server/mock list.
        }
    }

    func filtered(_ query: String) -> [Contact] {
        guard !query.isEmpty else { return contacts }
        return contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.phone.contains(query)
        }
    }

    /// Groups contacts into alphabetical sections.
    func sections(_ query: String) -> [(letter: String, items: [Contact])] {
        let list = filtered(query)
        let grouped = Dictionary(grouping: list) { contact -> String in
            let first = contact.displayName.trimmingCharacters(in: .whitespaces).first
            if let first, first.isLetter { return String(first).uppercased() }
            return "#"
        }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]!.sorted { $0.displayName < $1.displayName })
        }
    }
}

struct ContactsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = ContactsViewModel()
    @State private var query = ""
    @State private var selected: Contact?
    @State private var inviteTarget: Contact?

    var body: some View {
        VStack(spacing: 0) {
            // Search field pinned top.
            VStack(spacing: 0) {
                HStack {
                    Text("Contacts")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    // Header import action.
                    Button(action: { Task { await vm.importContacts() } }) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.Color.text)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(vm.isImporting)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)

                SearchField(text: $query, placeholder: "Search")
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
            }
            HairlineDivider()

            if vm.contacts.isEmpty && !vm.isLoading {
                VStack(spacing: Theme.Space.lg) {
                    EmptyStateView(message: "No contacts yet", systemImage: "person.2")
                    PrimaryButton(title: "Import contacts", isLoading: vm.isImporting) {
                        Task { await vm.importContacts() }
                    }
                    .padding(.horizontal, Theme.Space.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(vm.sections(query), id: \.letter) { section in
                            Section {
                                ForEach(section.items) { contact in
                                    ContactRow(contact: contact,
                                               onTap: { selected = contact },
                                               onInvite: { inviteTarget = contact })
                                    HairlineDivider(leadingInset: Theme.Space.lg + 40 + Theme.Space.md)
                                }
                            } header: {
                                SectionLetter(section.letter)
                            }
                        }
                    }
                    .padding(.bottom, Theme.Space.lg)
                }
            }
        }
        .background(Theme.Color.bg)
        .task { await vm.load() }
        .sheet(item: $selected) { contact in
            ContactSheet(contact: contact, onInvite: { inviteTarget = contact })
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $inviteTarget) { contact in
            InviteComposer(phone: contact.phone)
                .ignoresSafeArea()
        }
    }
}

private struct SectionLetter: View {
    let letter: String
    init(_ letter: String) { self.letter = letter }
    var body: some View {
        HStack {
            Text(letter)
                .uppercaseLabel()
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Color.bg)
    }
}

struct ContactRow: View {
    let contact: Contact
    let onTap: () -> Void
    let onInvite: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Space.md) {
                AvatarCircle(name: contact.displayName, size: 40)
                Text(contact.displayName)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                if !contact.onSlide {
                    Button(action: onInvite) {
                        Text("Invite")
                            .font(Theme.Font.buttonSmall)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
