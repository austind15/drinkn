import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @EnvironmentObject var auth: AuthManager
    let user: AppUser

    @State private var nickname: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile picture 📸") {
                    HStack(spacing: 16) {
                        Group {
                            if let img = pickedImage {
                                Image(uiImage: img).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable().scaledToFit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())

                        PhotosPicker("Choose photo", selection: $photoItem, matching: .images)
                    }
                }

                Section("Nickname 🍻") {
                    TextField("Pick a nickname", text: $nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let err = errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Welcome 👋")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .task(id: photoItem) {
                guard let item = photoItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickedImage = image
                }
            }
        }
    }

    private var canSave: Bool {
        nickname.trimmingCharacters(in: .whitespaces).count >= 2 && pickedImage != nil
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let updated = try await APIClient.shared.updateProfile(
                nickname: nickname.trimmingCharacters(in: .whitespaces),
                profilePicture: pickedImage
            )
            auth.completeProfile(user: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
