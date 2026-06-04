import SwiftUI

struct PhoneEntryView: View {
    @ObservedObject var vm: OnboardingViewModel
    @State private var showCountryPicker = false
    @FocusState private var phoneFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Your number")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("We'll text you a code.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            // Country code selector + phone input with a thin underline, big digits.
            VStack(spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.md) {
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: Theme.Space.xs) {
                            Text(vm.countryCode.flag)
                                .font(.system(size: 22))
                            Text(vm.countryCode.dialCode)
                                .font(Theme.Font.bigDigits)
                                .foregroundStyle(Theme.Color.text)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .light))
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())

                    TextField("123 456 7890", text: $vm.nationalNumber)
                        .font(Theme.Font.bigDigits)
                        .foregroundStyle(Theme.Color.text)
                        .tint(Theme.Color.accent)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($phoneFocused)
                }
                Rectangle()
                    .fill(phoneFocused ? Theme.Color.text : Theme.Color.hairline)
                    .frame(height: Theme.hairlineWidth)
                    .animation(Theme.Motion.standard, value: phoneFocused)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            Spacer()

            PrimaryButton(title: "Continue",
                          isLoading: vm.isSending,
                          isEnabled: vm.isPhoneValid) {
                Task {
                    if await vm.requestOtp() {
                        vm.code = ""
                        vm.path.append(.code)
                    }
                }
            }
            .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
        .background(Theme.Color.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { phoneFocused = true }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selection: $vm.countryCode)
        }
    }
}

struct CountryPickerView: View {
    @Binding var selection: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [CountryCode] {
        guard !query.isEmpty else { return CountryCode.all }
        return CountryCode.all.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.dialCode.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(text: $query, placeholder: "Search country")
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)

                List(filtered) { country in
                    Button {
                        selection = country
                        dismiss()
                    } label: {
                        HStack(spacing: Theme.Space.md) {
                            Text(country.flag).font(.system(size: 22))
                            Text(country.name)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Color.text)
                            Spacer()
                            Text(country.dialCode)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Color.textSecondary)
                            if country == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                    }
                    .listRowSeparatorTint(Theme.Color.hairline)
                    .listRowBackground(Theme.Color.bg)
                }
                .listStyle(.plain)
            }
            .background(Theme.Color.bg)
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.Color.text)
                }
            }
        }
    }
}
