import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("🍺")
                .font(.system(size: 80))
            VStack(spacing: 8) {
                Text("Drink-N")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .orange],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Text("Towards 1,000,000 🍺")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await auth.handleAppleAuthorization(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
