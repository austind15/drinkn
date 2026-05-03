import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager
    @State private var minSplashDone = false
    @AppStorage("ageGate.accepted") private var ageGateAccepted = false

    var body: some View {
        ZStack {
            if !ageGateAccepted {
                AgeGateView(hasAccepted: $ageGateAccepted)
            } else {
                switch auth.state {
                case .signedOut:
                    SignInView()
                case .needsProfile(let user):
                    ProfileSetupView(user: user)
                case .signedIn:
                    MainTabView()
                case .unknown:
                    Color.clear
                }
            }

            if showSplash {
                BeerSplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: showSplash)
        .task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            minSplashDone = true
        }
    }

    private var showSplash: Bool {
        if !minSplashDone { return true }
        if !ageGateAccepted { return false }
        if case .unknown = auth.state { return true }
        return false
    }
}
