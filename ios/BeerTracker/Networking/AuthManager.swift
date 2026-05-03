import Foundation
import Combine
import AuthenticationServices

@MainActor
final class AuthManager: ObservableObject {
    enum State {
        case unknown
        case signedOut
        case needsProfile(AppUser)
        case signedIn(AppUser)
    }

    @Published private(set) var state: State = .unknown

    func bootstrap() async {
        // Add a timeout to prevent getting stuck in .unknown state
        let bootstrapTask = Task {
            if await AuthStore.shared.token == nil {
                state = .signedOut
                return
            }
            do {
                let me = try await APIClient.shared.me()
                state = profileComplete(me) ? .signedIn(me) : .needsProfile(me)
            } catch {
                // Token present but invalid — clear it.
                await AuthStore.shared.setToken(nil)
                state = .signedOut
            }
        }

        // Wait up to 10 seconds for bootstrap to complete, otherwise default to signedOut
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            if case .unknown = state {
                state = .signedOut
            }
        }

        await bootstrapTask.value
        timeoutTask.cancel()
    }

    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            print("Apple sign-in failed: \(error)")
            return
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                return
            }
            do {
                let resp = try await APIClient.shared.signInWithApple(identityToken: identityToken)
                await AuthStore.shared.setToken(resp.token)
                state = resp.profileComplete ? .signedIn(resp.user) : .needsProfile(resp.user)
            } catch {
                print("Backend sign-in failed: \(error)")
            }
        }
    }

    func completeProfile(user: AppUser) {
        state = .signedIn(user)
    }

    func updateUser(_ user: AppUser) {
        if profileComplete(user) {
            state = .signedIn(user)
        } else {
            state = .needsProfile(user)
        }
    }

    func signOut() async {
        await AuthStore.shared.setToken(nil)
        state = .signedOut
    }

    private func profileComplete(_ user: AppUser) -> Bool {
        guard let url = user.profilePictureURL, !url.isEmpty else { return false }
        return !user.nickname.hasPrefix("user_")
    }
}
