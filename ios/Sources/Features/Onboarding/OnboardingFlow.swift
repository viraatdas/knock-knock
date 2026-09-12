import SwiftUI

/// Coordinates the phone-only, transport-first auth flow: Welcome -> Phone ->
/// Code. `AppState.didAuthenticate` takes it from there (profileSetup or
/// home, depending on `MeView.profileComplete`).
struct OnboardingFlow: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        NavigationStack(path: $vm.path) {
            WelcomeView { vm.path.append(OnboardingStep.phone) }
                .onAppear {
                    // Screenshot/debug hook (SPEC §2.5): `-scene phone`/`-scene code`.
                    guard vm.path.isEmpty else { return }
                    switch ProcessInfo.processInfo.arguments.sceneArgument {
                    case "phone":
                        vm.nationalNumber = "415 555 0123"
                        vm.path = [.phone]
                    case "code":
                        // Deliberately leave `vm.devCode` unset here: setting it
                        // shows the "Dev code: ..." convenience text, whose own
                        // `onAppear` auto-fills and submits the code — which would
                        // race straight through to profile setup instead of
                        // rendering the code-entry screen this scene is for.
                        vm.nationalNumber = "415 555 0123"
                        vm.path = [.phone, .code]
                    default:
                        break
                    }
                    #if DEBUG
                    // Real sign-in smoke test from the simulator, against a live
                    // backend + Firebase: `-sendCodeTo +1XXXXXXXXXX` prefills the
                    // number and presses Continue, so the whole transport chain
                    // (request-otp -> Firebase verify -> SMS) runs unattended.
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-sendCodeTo"), i + 1 < args.count {
                        let e164 = args[i + 1]
                        if let country = CountryCode.all.first(where: { e164.hasPrefix($0.dialCode) }) {
                            vm.countryCode = country
                            vm.nationalNumber = String(e164.dropFirst(country.dialCode.count))
                        }
                        vm.path = [.phone]
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            guard await vm.requestOtp() else { return }
                            vm.code = ""
                            vm.path.append(.code)
                            // `-verifyCodeFromFile <path>`: poll a host file for the
                            // six-digit SMS code and submit it, so the whole flow
                            // (verify -> /auth/firebase -> session) runs unattended.
                            guard let j = args.firstIndex(of: "-verifyCodeFromFile"), j + 1 < args.count else { return }
                            let path = args[j + 1]
                            for _ in 0..<300 {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                                let digits = raw.filter(\.isNumber)
                                if digits.count == 6 { vm.code = digits; break }
                            }
                        }
                    }
                    #endif
                }
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .phone:
                        PhoneEntryView(vm: vm)
                    case .code:
                        CodeEntryView(vm: vm) { user, isNew in
                            appState.didAuthenticate(user: user)
                        }
                    }
                }
        }
        .environmentObject(appState)
    }
}

enum OnboardingStep: Hashable { case phone, code }

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var path: [OnboardingStep] = []

    @Published var countryCode: CountryCode = .us
    @Published var nationalNumber: String = ""
    @Published var code: String = ""

    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var devCode: String?

    /// Firebase verification id, set by requestOtp when the server said
    /// `transport == "firebase"`.
    private var firebaseVerificationID: String?
    /// Which verification path the active request used, so verify() matches
    /// it: Firebase when the server said so; otherwise the backend OTP.
    private var usingFirebase = false

    private let api = APIClient.shared

    var e164: String {
        let digits = nationalNumber.filter(\.isNumber)
        return countryCode.dialCode + digits
    }

    var isPhoneValid: Bool {
        nationalNumber.filter(\.isNumber).count >= 7
    }

    /// `POST /auth/request-otp` first, then branch on `transport`:
    /// - "firebase": run Firebase phone verification ourselves. If it can't
    ///   send, show the error inline and never advance to the code screen.
    /// - "sms"/"review": the backend already sent (or simulated) the code;
    ///   advance to the code screen.
    func requestOtp() async -> Bool {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let resp = try await api.requestOtp(phone: e164)
            devCode = resp.devCode

            if resp.transport == "firebase" {
                #if canImport(FirebaseAuth)
                do {
                    firebaseVerificationID = try await FirebaseAuthService.sendCode(toE164: e164)
                    usingFirebase = true
                    reportDiagnostic(event: "otp_send_ok", detail: "firebase")
                    return true
                } catch {
                    usingFirebase = false
                    // Keep the message plain for the person stuck on it, but
                    // fold in the Firebase error code so a report from a
                    // reviewer's or user's device is actually diagnosable
                    // (see the 2.1a rejection this shipped to fix).
                    let firebaseError = error as? FirebaseAuthService.SendCodeError
                        ?? FirebaseAuthService.SendCodeError(underlying: error)
                    errorMessage = "We couldn't send a code. Try again in a minute. (Firebase \(firebaseError.code))"
                    reportDiagnostic(
                        event: "otp_send_failed",
                        detail: "firebase \(firebaseError.code) \(firebaseError.message)"
                    )
                    return false
                }
                #else
                errorMessage = "We couldn't send a code. Try again in a minute."
                reportDiagnostic(event: "otp_send_failed", detail: "firebase unavailable")
                return false
                #endif
            }

            usingFirebase = false
            reportDiagnostic(event: "otp_send_ok", detail: resp.transport)
            return true
        } catch {
            if Config.useMockData {
                // Offline: pretend it worked, surface a dev code.
                devCode = "123456"
                usingFirebase = false
                return true
            }
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func verify() async -> (MeView, Bool)? {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        #if canImport(FirebaseAuth)
        if usingFirebase, let vid = firebaseVerificationID {
            do {
                let idToken = try await FirebaseAuthService.verify(verificationID: vid, code: code)
                let resp = try await api.firebaseAuth(idToken: idToken)
                Haptics.success()
                return (resp.user, resp.isNewUser)
            } catch {
                Haptics.error()
                if let apiError = error as? APIError {
                    errorMessage = apiError.errorDescription
                } else {
                    // Firebase rejected the code (or couldn't finish sign-in).
                    // Keep the code visible so a review screenshot is diagnosable.
                    let nsError = error as NSError
                    let name = (nsError.userInfo["FIRAuthErrorUserInfoNameKey"] as? String) ?? ""
                    errorMessage = "Incorrect code. Try again. (Firebase \(nsError.code))"
                    let detail = "firebase \(nsError.code) \(name) \(nsError.localizedDescription)"
                    let country = countryCode.dialCode
                    Task { await APIClient.shared.reportDiagnostic(event: "otp_verify_failed", detail: detail, phoneCountry: country) }
                }
                return nil
            }
        }
        #endif

        do {
            let resp = try await api.verifyOtp(phone: e164, code: code)
            Haptics.success()
            return (resp.user, resp.isNewUser)
        } catch {
            if Config.useMockData {
                // Accept the dev code (or any 6 digits) offline.
                TokenStore.shared.save(access: "mock-access", refresh: "mock-refresh")
                Haptics.success()
                return (MockData.meIncomplete, true)
            }
            Haptics.error()
            errorMessage = (error as? APIError)?.errorDescription ?? "Incorrect code. Try again."
            return nil
        }
    }

    /// Fire-and-forget: never awaited by a caller, never surfaces its own
    /// errors, and must not delay or block the sign-in flow it reports on.
    /// `phoneCountry` is the dial code only, e.g. "+1" — never the full number.
    private func reportDiagnostic(event: String, detail: String) {
        let phoneCountry = countryCode.dialCode
        Task.detached(priority: .utility) {
            await APIClient.shared.reportDiagnostic(event: event, detail: detail, phoneCountry: phoneCountry)
        }
    }
}
