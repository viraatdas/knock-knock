import SwiftUI
import PhotosUI
import UIKit

/// Profile setup flow (SPEC §2.3). One NavigationStack-less sequence (back
/// allowed via a plain button, no push animation baggage), progress dots.
/// Init: `ProfileSetupFlow()`. `RootView` shows this whenever
/// `AppState.phase == .profileSetup`. Each step PATCHes through
/// `AppState.updateProfile(...)` immediately so a killed app resumes where it
/// left off; the last step flips `AppState.phase` to `.home`.
struct ProfileSetupFlow: View {
    @EnvironmentObject private var appState: AppState
    @State private var step: Step = Self.initialStep

    enum Step: Int, CaseIterable {
        case name, birthday, iAm, showMe, bioPhoto, location, notifications
    }

    /// Screenshot/debug hook (SPEC §2.5): `-scene setupName`/`-scene setupShowMe`.
    private static var initialStep: Step {
        ProcessInfo.processInfo.arguments.sceneArgument == "setupShowMe" ? .showMe : .name
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(total: Step.allCases.count, current: step.rawValue)
                .padding(.top, Theme.Space.lg)
                .padding(.bottom, Theme.Space.sm)

            Group {
                switch step {
                case .name:
                    NameStep(onNext: { step = .birthday })
                case .birthday:
                    BirthdayStep(onBack: { step = .name }, onNext: { step = .iAm })
                case .iAm:
                    IAmStep(onBack: { step = .birthday }, onNext: { step = .showMe })
                case .showMe:
                    ShowMeStep(onBack: { step = .iAm }, onNext: { step = .bioPhoto })
                case .bioPhoto:
                    BioPhotoStep(onBack: { step = .showMe }, onNext: { step = .location })
                case .location:
                    LocationStep(onBack: { step = .bioPhoto }, onNext: { step = .notifications })
                case .notifications:
                    NotificationsStep(onBack: { step = .location }, onFinish: { finishOnboarding() })
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.bg)
        .animation(Theme.Motion.standard, value: step)
        .onAppear { resumeAtFirstIncompleteStep() }
    }

    /// A profile that's already mostly filled in (e.g. routed back here for
    /// `location_required` from `/lobby/join`, per SPEC §1.6) should resume at
    /// the first thing actually missing rather than repeat the whole flow
    /// from Name. Only ever moves forward from the initial step, and never
    /// runs for a `-scene` screenshot launch (that already picked its step).
    private func resumeAtFirstIncompleteStep() {
        guard ProcessInfo.processInfo.arguments.sceneArgument == nil,
              let me = appState.me,
              let resumed = Self.firstIncompleteStep(for: me),
              resumed.rawValue > step.rawValue else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { step = resumed }
    }

    private static func firstIncompleteStep(for me: MeView) -> Step? {
        if (me.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return .name }
        if me.birthdate == nil { return .birthday }
        if me.gender == nil { return .iAm }
        if me.interestedIn.isEmpty { return .showMe }
        if !me.hasLocation { return .location }
        return nil
    }

    /// The end of the flow (NotificationsStep's onFinish). Only actually
    /// advances to Home when the server agrees the profile is complete —
    /// an earlier step's PATCH can have silently failed (offline, a dropped
    /// request), and forcing Home anyway just defers the confusion to a
    /// later 422 from `/lobby/join`. Falls back to resuming at whichever
    /// field is actually still missing instead (unlike
    /// `resumeAtFirstIncompleteStep`, this can move backward: notifications
    /// is the last step, so a forward-only jump would never trigger here).
    private func finishOnboarding() {
        guard let me = appState.me, let resumed = Self.firstIncompleteStep(for: me) else {
            appState.phase = .home
            return
        }
        step = resumed
    }
}

private struct ProgressDots: View {
    let total: Int
    let current: Int
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= current ? Theme.Color.accent : Theme.Color.hairline)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - 1. Name

private struct NameStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool
    let onNext: () -> Void

    var body: some View {
        KeyboardAvoidingScreen {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("What's your name?")
                        .font(Theme.Font.largeTitle)
                        .foregroundStyle(Theme.Color.text)
                    Text("This is what your dates will see.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.top, Theme.Space.lg)

                UnderlineField(placeholder: "Name", text: $name, contentType: .name,
                              autocapitalization: .words, submitLabel: .done) { save() }
                    .focused($focused)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.danger)
                }

                Spacer()
                PrimaryButton(title: "Continue", isLoading: isSaving,
                             isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
                    .padding(.bottom, Theme.Space.lg)
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .onAppear {
            name = appState.me?.displayName ?? ""
            focused = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let ok = await appState.updateProfile(displayName: trimmed)
            await MainActor.run {
                isSaving = false
                if ok { onNext() } else { errorMessage = "Couldn't save. Check your connection and try again." }
            }
        }
    }
}

// MARK: - 2. Birthday

private struct BirthdayStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var errorMessage: String?
    @State private var isSaving = false
    let onBack: () -> Void
    let onNext: () -> Void

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("When's your birthday?")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("You have to be 18 or older.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            DatePicker("Birthday", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            Spacer()
            TextLinkButton(title: "Back", action: onBack)
            PrimaryButton(title: "Continue", isLoading: isSaving) { save() }
                .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func save() {
        let age = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        guard age >= 18 else {
            errorMessage = "You have to be 18."
            return
        }
        errorMessage = nil
        isSaving = true
        Task {
            let ok = await appState.updateProfile(birthdate: Self.formatter.string(from: date))
            await MainActor.run {
                isSaving = false
                if ok { onNext() } else { errorMessage = "Couldn't save. Check your connection and try again." }
            }
        }
    }
}

// MARK: - 3. I am

private struct IAmStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var gender: Gender?
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text("I am")
                .font(Theme.Font.largeTitle)
                .foregroundStyle(Theme.Color.text)
                .padding(.top, Theme.Space.lg)

            HStack(spacing: Theme.Space.sm) {
                ForEach(Gender.allCases) { g in
                    Chip(title: g.label, isSelected: gender == g) { gender = g }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            Spacer()
            TextLinkButton(title: "Back", action: onBack)
            PrimaryButton(title: "Continue", isLoading: isSaving, isEnabled: gender != nil) { save() }
                .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
        .onAppear { gender = appState.me?.gender }
    }

    private func save() {
        guard let gender else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let ok = await appState.updateProfile(gender: gender)
            await MainActor.run {
                isSaving = false
                if ok { onNext() } else { errorMessage = "Couldn't save. Check your connection and try again." }
            }
        }
    }
}

// MARK: - 4. Show me

private struct ShowMeStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var interestedIn: Set<Gender> = []
    @State private var ageMin: Double = 18
    @State private var ageMax: Double = 99
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Show me")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("Pick everyone you're open to.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            HStack(spacing: Theme.Space.sm) {
                ForEach(Gender.allCases) { g in
                    Chip(title: g.label, isSelected: interestedIn.contains(g)) {
                        if interestedIn.contains(g) { interestedIn.remove(g) }
                        else { interestedIn.insert(g) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Ages \(Int(ageMin))\u{2013}\(Int(ageMax))").uppercaseLabel()
                RangeSlider(lowerValue: $ageMin, upperValue: $ageMax,
                            lowerLabel: "Minimum age", upperLabel: "Maximum age")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.danger)
            }

            Spacer()
            TextLinkButton(title: "Back", action: onBack)
            PrimaryButton(title: "Continue", isLoading: isSaving, isEnabled: !interestedIn.isEmpty) { save() }
                .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
        .onAppear {
            interestedIn = Set(appState.me?.interestedIn ?? [])
            ageMin = Double(appState.me?.ageMin ?? 18)
            ageMax = Double(appState.me?.ageMax ?? 99)
        }
    }

    private func save() {
        guard !interestedIn.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        Task {
            let ok = await appState.updateProfile(interestedIn: Array(interestedIn),
                                                   ageMin: Int(ageMin), ageMax: Int(ageMax))
            await MainActor.run {
                isSaving = false
                if ok { onNext() } else { errorMessage = "Couldn't save. Check your connection and try again." }
            }
        }
    }
}

// MARK: - 5. Bio + photo

private struct BioPhotoStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var bio: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        KeyboardAvoidingScreen {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("A photo and a line about you")
                        .font(Theme.Font.largeTitle)
                        .foregroundStyle(Theme.Color.text)
                    Text("Both optional. You can add them later.")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.top, Theme.Space.lg)

                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        if let pickedImage {
                            Image(uiImage: pickedImage)
                                .resizable().scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                        } else {
                            ZStack {
                                Circle().fill(Theme.Color.bgGrouped)
                                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                                Image(systemName: "camera")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            .frame(width: 96, height: 96)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    Spacer()
                }

                TextField("A line about you", text: $bio, axis: .vertical)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.text)
                    .lineLimit(3...6)
                    .onChange(of: bio) { _, v in if v.count > 300 { bio = String(v.prefix(300)) } }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Color.danger)
                }

                Spacer()
                TextLinkButton(title: "Back", action: onBack)
                PrimaryButton(title: "Continue", isLoading: isSaving) { save() }
                    .padding(.bottom, Theme.Space.lg)
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .onAppear { bio = appState.me?.bio ?? "" }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickedImage = image
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            var ok = true
            if let pickedImage, let data = pickedImage.resizedJPEGData() {
                ok = await appState.uploadPhoto(data)
            }
            if ok {
                ok = await appState.updateProfile(bio: bio)
            }
            await MainActor.run {
                isSaving = false
                if ok { onNext() } else { errorMessage = "Couldn't save. Check your connection and try again." }
            }
        }
    }
}

// MARK: - 6. Location

private struct LocationStep: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var location = LocationService.shared
    @State private var isRequesting = false
    @State private var infoMessage: String?
    let onBack: () -> Void
    let onNext: () -> Void

    /// Mirrors TonightView's location nag: once permission has actually been
    /// denied, re-asking does nothing (no system dialog can reappear), so the
    /// button sends the user to Settings instead of silently no-op-ing.
    private var buttonTitle: String {
        location.isDenied ? "Open settings" : "Turn on location"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Find people nearby")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("We match you with people within 75 miles. Your location is stored rounded to about a kilometer.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            if let infoMessage {
                Text(infoMessage)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Spacer()

            TextLinkButton(title: "Back", action: onBack)
            PrimaryButton(title: buttonTitle, isLoading: isRequesting) {
                Task { await requestLocation() }
            }
            TextLinkButton(title: "Skip for now", action: onNext)
                .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func requestLocation() async {
        if location.isDenied {
            infoMessage = "Location is off. Turn it on in Settings, then come back here."
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
            return
        }
        isRequesting = true
        infoMessage = nil
        if !location.isAuthorized {
            location.requestWhenInUseAuthorization()
            // Wait for the real authorization decision instead of a fixed
            // sleep — the system permission dialog can't possibly be
            // answered within a fraction of a second, and a fixed delay just
            // moves on as if the user had said no.
            var waited = 0
            while !location.isAuthorized && !location.isDenied && waited < 50 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                waited += 1
            }
        }
        guard location.isAuthorized else {
            isRequesting = false
            infoMessage = "Location is off. You can still turn it on later from the Tonight tab."
            return
        }
        let ok = await appState.submitLocation()
        isRequesting = false
        if ok {
            onNext()
        } else {
            infoMessage = "Couldn't save your location. Check your connection and try again."
        }
    }
}

// MARK: - 7. Notifications

private struct NotificationsStep: View {
    @State private var isRequesting = false
    let onBack: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("We'll knock at 7")
                    .font(Theme.Font.largeTitle)
                    .foregroundStyle(Theme.Color.text)
                Text("A notification when doors open, plus your matches and messages.")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.top, Theme.Space.lg)

            Spacer()
            TextLinkButton(title: "Back", action: onBack)
            PrimaryButton(title: "Turn on notifications", isLoading: isRequesting) {
                Task {
                    isRequesting = true
                    _ = await NotificationService.requestAuthorization()
                    NotificationService.registerForRemoteNotifications()
                    NotificationService.scheduleDoorsOpenReminder()
                    isRequesting = false
                    onFinish()
                }
            }
            TextLinkButton(title: "Not now", action: onFinish)
                .padding(.bottom, Theme.Space.lg)
        }
        .padding(.horizontal, Theme.Space.lg)
    }
}
