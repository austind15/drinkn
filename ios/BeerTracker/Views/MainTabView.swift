import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            FeedView()
                .tabItem { Label("Feed", systemImage: "list.bullet.rectangle.portrait.fill") }

            LogBeerView()
                .tabItem { Label("Log", systemImage: "plus.circle.fill") }

            SocialView()
                .tabItem { Label("Social", systemImage: "person.2.fill") }

            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
        }
        .tint(.orange)
    }
}
