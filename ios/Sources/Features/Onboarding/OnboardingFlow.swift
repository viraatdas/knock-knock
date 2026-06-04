import SwiftUI

/// Coordinates the phone-only auth flow: Welcome -> Phone -> Code.
/// (Name step happens after auth, driven by AppPhase.needsName.)
struct OnboardingFlow: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = OnboardingViewModel()

    var body: some View {
        NavigationStack(path: $vm.path) {
            WelcomeView { vm.path.append(OnboardingStep.phone) }
                .onAppear {
                    // Debug/screenshot hooks so flows can be reached deterministically
                    // in the simulator (no signing / no live backend required).
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-startPhone"), vm.path.isEmpty {
                        vm.nationalNumber = "415 555 0123"
                        vm.path = [.phone]
                    } else if args.contains("-startCode"), vm.path.isEmpty {
                        vm.nationalNumber = "415 555 0123"
                        vm.devCode = "123456"
                        vm.path = [.phone, .code]
                    }
                }
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .phone:
                        PhoneEntryView(vm: vm)
                    case .code:
                        CodeEntryView(vm: vm) { user, isNew in
                            appState.didAuthenticate(user: user, isNewUser: isNew)
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

    /// Firebase verification id, set by requestOtp when Firebase auth is active.
    private var firebaseVerificationID: String?

    private let api = APIClient.shared

    var e164: String {
        let digits = nationalNumber.filter(\.isNumber)
        return countryCode.dialCode + digits
    }

    var isPhoneValid: Bool {
        nationalNumber.filter(\.isNumber).count >= 7
    }

    func requestOtp() async -> Bool {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth {
            do {
                firebaseVerificationID = try await FirebaseAuthService.sendCode(toE164: e164)
                return true
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        #endif

        do {
            let resp = try await api.requestOtp(phone: e164)
            devCode = resp.devCode
            return true
        } catch {
            if Config.useMockData {
                // Offline: pretend it worked, surface a dev code.
                devCode = "123456"
                return true
            }
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func verify() async -> (User, Bool)? {
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        #if canImport(FirebaseAuth)
        if Config.useFirebaseAuth, let vid = firebaseVerificationID {
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
            Haptics.success()   // signed in
            return (resp.user, resp.isNewUser)
        } catch {
            if Config.useMockData {
                // Accept the dev code (or any 6 digits) offline.
                TokenStore.shared.save(access: "mock-access", refresh: "mock-refresh")
                Haptics.success()
                let isNew = true
                let user = User(id: "u_me", phone: e164, displayName: nil,
                                avatarUrl: nil, createdAt: Date(), lastSeenAt: Date())
                return (user, isNew)
            }
            Haptics.error()
            errorMessage = (error as? APIError)?.errorDescription ?? "Incorrect code. Try again."
            return nil
        }
    }
}
