import SwiftUI

/// "Call anyone" entry: type a phone number, and if they're on Slide you can
/// call them directly. No need to be in each other's contacts. Slide only
/// requires that the person has Slide.
struct DialView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var number = ""
    @State private var country = CountryCode.us
    @State private var showCountryPicker = false
    @State private var checking = false
    @State private var result: LookupResult?

    private let api = APIClient.shared

    enum LookupResult: Equatable {
        case onSlide(userId: String, name: String)
        case notOnSlide
        case error(String)
    }

    private var nationalDigits: String { PhoneNumberFormatting.digits(number) }
    private var e164: String { country.dialCode + nationalDigits }
    private var canCheck: Bool { nationalDigits.count >= 4 }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Callpad")
                        .font(Theme.Font.largeTitle)
                        .foregroundStyle(Theme.Color.text)
                }

                // Number entry with country selector.
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Phone number")
                        .uppercaseLabel()
                    HStack(spacing: Theme.Space.md) {
                        Button { showCountryPicker = true } label: {
                            HStack(spacing: Theme.Space.xs) {
                                Text(country.flag).font(.system(size: 22))
                                Text(country.dialCode)
                                    .font(Theme.Font.bigDigits)
                                    .foregroundStyle(Theme.Color.text)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())

                        TextField("123 456 7890", text: $number)
                            .font(Theme.Font.bigDigits)
                            .foregroundStyle(Theme.Color.text)
                            .keyboardType(.phonePad)
                            .onChange(of: number) { _, newValue in
                                formatNumber(newValue)
                                result = nil
                            }
                    }
                    Rectangle()
                        .fill(Theme.Color.hairline)
                        .frame(height: Theme.hairlineWidth)
                }

                // Result / action.
                switch result {
                case .onSlide(let userId, let name):
                    VStack(spacing: Theme.Space.md) {
                        HStack(spacing: Theme.Space.md) {
                            AvatarCircle(name: name, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name).font(Theme.Font.body).foregroundStyle(Theme.Color.text)
                                Text("On Slide").font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            Spacer()
                        }
                        PrimaryButton(title: "Tap") { tap(userId: userId, name: name) }
                        HStack(spacing: Theme.Space.md) {
                            PrimaryButton(title: "Audio") { call(userId: userId, name: name, video: false) }
                            PrimaryButton(title: "Video") { call(userId: userId, name: name, video: true) }
                        }
                    }
                case .notOnSlide:
                    Text("Not on Slide yet")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                case .error(let msg):
                    Text(msg).font(Theme.Font.callout).foregroundStyle(Theme.Color.danger)
                case nil:
                    PrimaryButton(title: "Find on Slide", isLoading: checking, isEnabled: canCheck) {
                        Task { await check() }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.lg)
            .background(Theme.Color.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Color.text)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerView(selection: $country)
            }
            .onChange(of: country) { _, _ in formatNumber(number) }
        }
    }

    private func formatNumber(_ value: String) {
        let formatted = PhoneNumberFormatting.national(value, country: country)
        if formatted != value {
            number = formatted
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let results = try await api.syncContacts(phones: [e164])
            if let r = results.first, r.onSlide, let uid = r.userId {
                result = .onSlide(userId: uid, name: r.displayName ?? e164)
                Haptics.success()
            } else {
                result = .notOnSlide
                Haptics.warning()
            }
        } catch {
            if Config.useMockData {
                // Demo: pretend the number is on Slide so the flow is testable.
                result = .onSlide(userId: "u_\(e164)", name: e164)
                Haptics.success()
            } else {
                result = .error("Couldn't check that number. Try again.")
                Haptics.error()
            }
        }
    }

    private func call(userId: String, name: String, video: Bool) {
        let user = User(id: userId, phone: e164, displayName: name,
                        avatarUrl: nil, createdAt: nil, lastSeenAt: nil)
        dismiss()
        appState.startCall(to: user, video: video)
    }

    private func tap(userId: String, name: String) {
        let user = User(id: userId, phone: e164, displayName: name,
                        avatarUrl: nil, createdAt: nil, lastSeenAt: nil)
        dismiss()
        appState.startKnockCall(to: user)
    }
}
