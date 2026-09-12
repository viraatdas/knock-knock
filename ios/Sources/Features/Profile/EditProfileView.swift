import SwiftUI
import PhotosUI

/// Edit profile sheet (SPEC §2.3 "Edit profile"). Init: `EditProfileView()`.
/// Reads `AppState.me`; saves through `AppState.updateProfile(...)`,
/// `AppState.uploadPhoto(_:)` and `AppState.deletePhoto()`.
struct EditProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var gender: Gender?
    @State private var interestedIn: Set<Gender> = []
    @State private var ageMin: Double = 18
    @State private var ageMax: Double = 99
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.sm) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            if let pickedImage {
                                Image(uiImage: pickedImage).resizable().scaledToFill()
                                    .frame(width: 96, height: 96).clipShape(Circle())
                                    .overlay(Circle().stroke(Theme.Color.hairline, lineWidth: 1))
                            } else {
                                PhotoAvatar(profile: currentProfile, size: 96)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                        if appState.me?.hasPhoto == true || pickedImage != nil {
                            TextLinkButton(title: "Remove photo", color: Theme.Color.warm) {
                                pickedImage = nil
                                Task { await appState.deletePhoto() }
                            }
                        }
                    }
                    .padding(.top, Theme.Space.lg)

                    UnderlineField(placeholder: "Name", text: $displayName,
                                  contentType: .name, autocapitalization: .words)

                    if let birthdate = appState.me?.birthdate {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(bornLine(birthdate))
                                .font(Theme.Font.callout)
                                .foregroundStyle(Theme.Color.text)
                            Link("Wrong? Tell us",
                                destination: URL(string: "mailto:viraat@exla.ai?subject=Birthday%20correction")!)
                                .font(Theme.Font.footnote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("I am").uppercaseLabel()
                        HStack(spacing: Theme.Space.sm) {
                            ForEach(Gender.allCases) { g in
                                Chip(title: g.label, isSelected: gender == g) { gender = g }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Show me").uppercaseLabel()
                        HStack(spacing: Theme.Space.sm) {
                            ForEach(Gender.allCases) { g in
                                Chip(title: g.label, isSelected: interestedIn.contains(g)) {
                                    if interestedIn.contains(g) { interestedIn.remove(g) }
                                    else { interestedIn.insert(g) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Text("Ages \(Int(ageMin))\u{2013}\(Int(ageMax))").uppercaseLabel()
                        HStack(spacing: Theme.Space.lg) {
                            Stepper("Min \(Int(ageMin))", value: $ageMin, in: 18...ageMax, step: 1)
                            Stepper("Max \(Int(ageMax))", value: $ageMax, in: ageMin...99, step: 1)
                        }
                        .font(Theme.Font.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack {
                            Text("Bio").uppercaseLabel()
                            Spacer()
                            Text("\(bio.count)/300")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                        TextField("A line about you", text: $bio, axis: .vertical)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Color.text)
                            .lineLimit(3...6)
                            .onChange(of: bio) { _, v in if v.count > 300 { bio = String(v.prefix(300)) } }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.Font.footnote)
                            .foregroundStyle(Theme.Color.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.Color.bg)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    }
                }
            }
        }
    }

    private var currentProfile: PublicProfile? {
        guard let me = appState.me else { return nil }
        return PublicProfile(id: me.id, displayName: me.displayName ?? "", age: me.age,
                             gender: me.gender, bio: me.bio, hasPhoto: me.hasPhoto,
                             photoUrl: me.photoUrl, distanceMiles: nil)
    }

    private static let birthdateParser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static let birthdateDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    /// "Born April 2, 1996 · 30" (SPEC §2.3). `birthdate` comes over the wire
    /// as `yyyy-MM-dd`; falls back to the raw string if it ever fails to parse.
    private func bornLine(_ birthdate: String) -> String {
        let spelled = Self.birthdateParser.date(from: birthdate)
            .map { Self.birthdateDisplay.string(from: $0) } ?? birthdate
        guard let age = appState.me?.age else { return "Born \(spelled)" }
        return "Born \(spelled) \u{00b7} \(age)"
    }

    private func load() {
        guard let me = appState.me else { return }
        displayName = me.displayName ?? ""
        bio = me.bio
        gender = me.gender
        interestedIn = Set(me.interestedIn)
        ageMin = Double(me.ageMin)
        ageMax = Double(me.ageMax)
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
                ok = await appState.updateProfile(
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    gender: gender,
                    interestedIn: Array(interestedIn),
                    ageMin: Int(ageMin), ageMax: Int(ageMax),
                    bio: bio)
            }
            await MainActor.run {
                isSaving = false
                if ok {
                    dismiss()
                } else {
                    errorMessage = "Couldn't save. Check your connection and try again."
                }
            }
        }
    }
}
