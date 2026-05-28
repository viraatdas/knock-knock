import SwiftUI

struct CodeEntryView: View {
    @ObservedObject var vm: OnboardingViewModel
    let onVerified: (User, Bool) -> Void

    @FocusState private var focused: Bool
    @State private var resendIn: Int = 30
    @State private var timer: Timer?

    private let length = 6

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Enter code")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("Sent to \(vm.e164)")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            // 6 auto-advancing boxes overlaying a hidden field.
            ZStack {
                TextField("", text: $vm.code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accentColor(.clear)
                    .onChange(of: vm.code) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(length))
                        if digits != newValue { vm.code = digits }
                        if digits.count == length { submit() }
                    }

                HStack(spacing: Theme.Space.sm) {
                    ForEach(0..<length, id: \.self) { i in
                        OTPBox(digit: digit(at: i),
                               isActive: i == vm.code.count && focused)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            // Resend link with countdown.
            HStack(spacing: Theme.Space.xs) {
                Text("Didn't get it?")
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
                if resendIn > 0 {
                    Text("Resend in \(resendIn)s")
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    Button("Resend") { resend() }
                        .font(Theme.Font.buttonSmall)
                        .foregroundStyle(Theme.Color.text)
                }
            }

            if let dev = vm.devCode {
                Text("Dev code: \(dev)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .onAppear { vm.code = dev }
            }

            Spacer()

            if vm.isSending {
                HStack { Spacer(); ProgressView().tint(Theme.Color.accent); Spacer() }
                    .padding(.bottom, Theme.Space.lg)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .background(Theme.Color.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            focused = true
            startCountdown()
        }
        .onDisappear { timer?.invalidate() }
    }

    private func digit(at index: Int) -> String {
        let chars = Array(vm.code)
        return index < chars.count ? String(chars[index]) : ""
    }

    private func submit() {
        focused = false
        Task {
            if let (user, isNew) = await vm.verify() {
                onVerified(user, isNew)
            } else {
                vm.code = ""
                focused = true
            }
        }
    }

    private func resend() {
        Task {
            _ = await vm.requestOtp()
            resendIn = 30
            startCountdown()
        }
    }

    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            Task { @MainActor in
                if resendIn > 0 { resendIn -= 1 } else { t.invalidate() }
            }
        }
    }
}

private struct OTPBox: View {
    let digit: String
    let isActive: Bool

    var body: some View {
        Text(digit)
            .font(Theme.Font.bigDigits)
            .foregroundStyle(Theme.Color.text)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? Theme.Color.text :
                            (digit.isEmpty ? Theme.Color.hairline : Theme.Color.text))
                    .frame(height: isActive ? 2 : Theme.hairlineWidth)
                    .animation(Theme.Motion.fast, value: isActive)
            }
    }
}
