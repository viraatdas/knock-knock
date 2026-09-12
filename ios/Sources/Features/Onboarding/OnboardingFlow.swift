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
                errorMessage = (error as? APIError)?.errorDescription ?? "Incorrect code. Try again."
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
