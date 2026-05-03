import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var newImage: UIImage?
    @State private var saving = false
    @State private var error: String?

    private var currentUser: AppUser? {
        if case .signedIn(let user) = auth.state { return user }
        if case .needsProfile(let user) = auth.state { return user }
        return nil
    }

    var body: some View {
        Form {
            if let user = currentUser {
                Section("Profile") {
                    HStack(spacing: 16) {
                        Group {
                            if let img = newImage {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                RemoteImage(string: user.profilePictureURL)
                            }
                        }
                        .frame(width: 64, height: 64).clipShape(Circle())
                        PhotosPicker("Change photo", selection: $photoItem, matching: .images)
                    }
                    TextField("Nickname", text: $nickname)
                        .onAppear { if nickname.isEmpty { nickname = user.nickname } }
                }
                Section {
                    Button(saving ? "Saving…" : "Save changes") { Task { await save() } }
                        .disabled(saving)
                }
            }

            if let err = error { Section { Text(err).foregroundStyle(.red) } }

            Section {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() ; dismiss() }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                newImage = image
            }
        }
    }

    private func save() async {
        saving = true
        error = nil
        do {
            let updated = try await APIClient.shared.updateProfile(
                nickname: nickname.trimmingCharacters(in: .whitespaces),
                profilePicture: newImage
            )
            auth.updateUser(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
