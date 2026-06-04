import SwiftUI

/// Multi-select sheet to start a group call. Pick two or more people, choose
/// audio or video, and place the call. The backend rings everyone and the SFU
/// fans out each participant's media.
struct GroupCallPicker: View {
    let contacts: [Contact]
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedIds: Set<String> = []

    private var filtered: [Contact] {
        // Only people on Slide can be in a group call — calling a non-Slide
        // number would fail server-side (no real user id). Dedupe by Slide user.
        var seen = Set<String>()
        let onSlide = contacts.filter { c in
            guard c.onSlide, let uid = c.contactUserId else { return false }
            return seen.insert(uid).inserted
        }
        let base = onSlide.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.phone.contains(query)
        }
    }

    private var selectedContacts: [Contact] {
        contacts.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(text: $query, placeholder: "Search")
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)

                if !selectedContacts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.md) {
                            ForEach(selectedContacts) { c in
                                VStack(spacing: 4) {
                                    AvatarCircle(name: c.displayName, size: 48)
                                    Text(c.displayName.split(separator: " ").first.map(String.init) ?? "")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 60)
                                .onTapGesture { selectedIds.remove(c.id) }
                            }
                        }
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.bottom, Theme.Space.sm)
                    }
                }
                HairlineDivider()

                List(filtered) { contact in
                    Button {
                        toggle(contact)
                    } label: {
                        HStack(spacing: Theme.Space.md) {
                            AvatarCircle(name: contact.displayName, size: 40)
                            Text(contact.displayName)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Color.text)
                            Spacer()
                            Image(systemName: selectedIds.contains(contact.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .light))
                                .foregroundStyle(selectedIds.contains(contact.id)
                                                 ? Theme.Color.accent : Theme.Color.hairline)
                        }
                    }
                    .listRowBackground(Theme.Color.bg)
                    .listRowSeparatorTint(Theme.Color.hairline)
                }
                .listStyle(.plain)

                // Call actions.
                HStack(spacing: Theme.Space.md) {
                    PrimaryButton(title: "Audio",
                                  isEnabled: selectedIds.count >= 2) {
                        place(video: false)
                    }
                    PrimaryButton(title: "Video",
                                  isEnabled: selectedIds.count >= 2) {
                        place(video: true)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
                .padding(.top, Theme.Space.sm)
            }
            .background(Theme.Color.bg)
            .navigationTitle("New group call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Color.text)
                }
            }
        }
    }

    private func toggle(_ contact: Contact) {
        Haptics.select()
        if selectedIds.contains(contact.id) { selectedIds.remove(contact.id) }
        else { selectedIds.insert(contact.id) }
    }

    private func place(video: Bool) {
        let users = selectedContacts.map { MockData.userForContact($0) }
        dismiss()
        appState.startGroupCall(to: users, video: video)
    }
}
