import SwiftUI
import Contacts

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    @Published var isImporting = false

    private let api = APIClient.shared
    private var activeLoadCount = 0
    private var latestLoadGeneration = 0

    func load(showLoading: Bool = true, force: Bool = false) async {
        if activeLoadCount > 0 && !force { return }
        latestLoadGeneration += 1
        let generation = latestLoadGeneration
        activeLoadCount += 1
        if showLoading { isLoading = true }
        defer {
            activeLoadCount -= 1
            if showLoading && generation == latestLoadGeneration { isLoading = false }
        }
        do {
            let list = try await api.contacts()
            guard generation == latestLoadGeneration else { return }
            replaceContacts(list)
        } catch {
            guard generation == latestLoadGeneration else { return }
            if Config.useMockData {
                replaceContacts(MockData.contacts)
            }
        }
    }

    func replaceContacts(_ list: [Contact]) {
        contacts = list.sorted { $0.displayName < $1.displayName }
    }

    /// User-triggered: request Contacts permission, read names + numbers, sync,
    /// then refresh so on-Slide vs not is reflected.
    func importContacts() async {
        isImporting = true
        defer { isImporting = false }
        await syncDeviceContacts()
        await load(force: true)
        Haptics.success()   // import finished
    }

    private func syncDeviceContacts() async {
        let store = CNContactStore()
        guard CNContactStore.authorizationStatus(for: .contacts) != .denied else { return }
        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return }
            // Use CNContactFormatter's key descriptor so we capture EVERY name
            // form (given/family, nickname, company-only, non-Western order),
            // not just first+last — otherwise lots of contacts show as a number.
            let keys: [CNKeyDescriptor] = [
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            // Keep names aligned 1:1 with phones so the server can store the
            // address-book name for each number (otherwise contacts show as "?").
            var phones: [String] = []
            var names: [String] = []
            try store.enumerateContacts(with: request) { contact, _ in
                // Best available name: formatted full name → nickname → company.
                var name = CNContactFormatter.string(from: contact, style: .fullName)?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if name.isEmpty { name = contact.nickname.trimmingCharacters(in: .whitespaces) }
                if name.isEmpty { name = contact.organizationName.trimmingCharacters(in: .whitespaces) }
                for number in contact.phoneNumbers {
                    let raw = number.value.stringValue.trimmingCharacters(in: .whitespaces)
                    guard !raw.isEmpty else { continue }
                    phones.append(raw)
                    // Fall back to the number itself only if truly no name exists.
                    names.append(name.isEmpty ? raw : name)
                }
            }
            if !phones.isEmpty {
                _ = try? await api.syncContacts(
                    phones: Array(phones.prefix(1000)),
                    names: Array(names.prefix(1000)))
            }
        } catch {
            // Ignore; falls back to server/mock list.
        }
    }

    /// Filter + dedupe. Contacts can have multiple rows for the same person
    /// (several phone numbers); collapse by Slide user id when on Slide, else by
    /// normalized name+phone, so the list isn't cluttered with duplicates.
    func filtered(_ query: String) -> [Contact] {
        let base = query.isEmpty ? contacts : contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.phone.contains(query)
        }
        var seen = Set<String>()
        var out: [Contact] = []
        for c in base {
            let key = c.contactUserId ?? "\(c.displayName.lowercased())|\(c.phone)"
            if seen.insert(key).inserted { out.append(c) }
        }
        return out
    }

    /// People already on Slide — these are directly callable. Deduped + name-sorted.
    func onSlide(_ query: String) -> [Contact] {
        filtered(query).filter { $0.onSlide }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// People not yet on Slide — shown with an Invite action.
    func notOnSlide(_ query: String) -> [Contact] {
        filtered(query).filter { !$0.onSlide }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

struct ContactsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = ContactsViewModel()
    @State private var query = ""
    @State private var selected: Contact?
    @State private var inviteTarget: Contact?
    @State private var showGroupPicker = false
    @State private var showDial = false

    var body: some View {
        VStack(spacing: 0) {
            // Search field pinned top.
            VStack(spacing: 0) {
                HStack {
                    Text("Contacts")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.text)
                    Spacer()
                    // Call anyone by number.
                    Button(action: { showDial = true }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.Color.text)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Call by number")
                    // Start a group call.
                    Button(action: { showGroupPicker = true }) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Theme.Color.text)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("New group call")
                    // Header import action.
                    Button(action: { Task { await importContacts() } }) {
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
                VStack(spacing: Theme.Space.xl) {
                    EmptyStateView(message: "No contacts yet", systemImage: "person.2")
                    Text("Import your contacts to see who's already on Slide. You can call anyone on Slide, friends or not.")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.xxl)
                    PrimaryButton(title: "Import contacts", isLoading: vm.isImporting) {
                        Task { await importContacts() }
                    }
                    .padding(.horizontal, Theme.Space.xxl)
                    // Extra breathing room beneath the button so it isn't crowded.
                    .padding(.top, Theme.Space.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, Theme.Space.xxl)
            } else {
                let onSlide = vm.onSlide(query)
                let invitable = vm.notOnSlide(query)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // People you can call right now.
                        if !onSlide.isEmpty {
                            Section {
                                ForEach(onSlide) { contact in
                                    ContactRow(contact: contact,
                                               onTap: { selected = contact },
                                               onInvite: { inviteTarget = contact })
                                    HairlineDivider(leadingInset: Theme.Space.lg + 44 + Theme.Space.md)
                                }
                            } header: {
                                SectionHeaderLabel(title: "On Slide", count: onSlide.count)
                            }
                        }

                        // Everyone else, with an invite.
                        if !invitable.isEmpty {
                            Section {
                                ForEach(invitable) { contact in
                                    ContactRow(contact: contact,
                                               onTap: { inviteTarget = contact },
                                               onInvite: { inviteTarget = contact })
                                    HairlineDivider(leadingInset: Theme.Space.lg + 44 + Theme.Space.md)
                                }
                            } header: {
                                SectionHeaderLabel(title: "Invite to Slide", count: invitable.count)
                            }
                        }

                        if onSlide.isEmpty && invitable.isEmpty {
                            Text("No matches")
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Theme.Space.xxl)
                        }
                    }
                    // Extra bottom padding so the last row clears the tab bar and
                    // the import button isn't crammed against the edge.
                    .padding(.bottom, Theme.Space.xxl * 2)
                }
            }
        }
        .background(Theme.Color.bg)
        .task {
            await refreshContacts()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await refreshContacts(showLoading: false)
            }
        }
        .refreshable {
            await refreshContacts(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshContacts(showLoading: false) }
        }
        .sheet(item: $selected) { contact in
            ContactSheet(contact: contact, onInvite: { inviteTarget = contact })
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGroupPicker) {
            GroupCallPicker(contacts: vm.contacts)
                .environmentObject(appState)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showDial) {
            DialView()
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $inviteTarget) { contact in
            InviteComposer(phone: contact.phone)
                .ignoresSafeArea()
        }
    }

    private func importContacts() async {
        await vm.importContacts()
        appState.replaceContactCache(vm.contacts)
    }

    private func refreshContacts(showLoading: Bool = true, force: Bool = false) async {
        await vm.load(showLoading: showLoading, force: force)
        appState.replaceContactCache(vm.contacts)
    }
}

private struct SectionHeaderLabel: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text(title).uppercaseLabel()
            Text("\(count)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.xs)
        .background(Theme.Color.bg)
    }
}

struct ContactRow: View {
    let contact: Contact
    let onTap: () -> Void
    let onInvite: () -> Void

    private var subtitle: String {
        // Show the number unless the display name already is the number.
        contact.displayName == contact.phone ? "On Slide" : contact.phone
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.Space.md) {
                AvatarCircle(name: contact.displayName,
                             imageURL: contact.avatarUrl.flatMap(URL.init(string:)),
                             size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(contact.displayName.isEmpty ? contact.phone : contact.displayName)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(1)
                    Text(contact.onSlide ? "On Slide" : subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if contact.onSlide {
                    // Direct call affordance — calling is one tap.
                    Image(systemName: "video")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(Theme.Color.text)
                } else {
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
