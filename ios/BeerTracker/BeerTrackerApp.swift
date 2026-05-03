import SwiftUI

@main
struct BeerTrackerApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var groupFilter = GroupFilterStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(groupFilter)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .task { await auth.bootstrap() }
        }
    }
}
