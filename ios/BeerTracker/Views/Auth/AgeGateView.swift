import SwiftUI

/// Shown on first launch (and persists via UserDefaults). Confirms the
/// user is of legal drinking age and surfaces the responsible-drinking
/// disclaimer before they can use the app.
struct AgeGateView: View {
    @Binding var hasAccepted: Bool
    @State private var showDeclined = false

    private let tosURL = URL(string: "https://www.notion.so/Drink-N-Terms-of-Service-3543963ceb7b80959946f95264976192?source=copy_link")!
    private let privacyURL = URL(string: "https://www.notion.so/Drink-N-Privacy-policy-3543963ceb7b80ecaa83f119a6bd4329?source=copy_link")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("🍻")
                    .font(.system(size: 72))
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Welcome to Drink-N")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Before you continue, please confirm a few things.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Divider().padding(.vertical, 8)

                Group {
                    Label("You are 21 or older (or the legal drinking age in your country, whichever is higher).", systemImage: "person.fill.checkmark")
                    Label("Drink-N is for entertainment. It is not a health or medical tool.", systemImage: "exclamationmark.triangle.fill")
                    Label("Drink responsibly. Never drink and drive. If alcohol is harming you or someone you love, get help — SAMHSA: 1-800-662-4357.", systemImage: "heart.fill")
                    Label("You use this app at your own risk. The developer is not liable for the consequences of your choices.", systemImage: "hand.raised.fill")
                }
                .font(.callout)
                .foregroundStyle(.primary)

                Divider().padding(.vertical, 8)

                HStack(spacing: 16) {
                    Link("Terms of Service", destination: tosURL)
                    Link("Privacy Policy", destination: privacyURL)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 12) {
                    Button {
                        hasAccepted = true
                    } label: {
                        Text("I'm 21+ and I agree")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)

                    Button(role: .cancel) {
                        showDeclined = true
                    } label: {
                        Text("I don't agree")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
        .alert("Drink-N is for users 21+", isPresented: $showDeclined) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can't use the app without agreeing to the terms. You can close the app from the home screen.")
        }
    }
}
