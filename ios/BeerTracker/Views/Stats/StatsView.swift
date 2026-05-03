import SwiftUI

struct StatsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("You") {
                    NavigationLink { MyStatsView() } label: { Label("My stats", systemImage: "person.fill") }
                    NavigationLink { PhotoGalleryView() } label: { Label("My photos", systemImage: "photo.on.rectangle.angled") }
                }
                Section("Leaderboards") {
                    NavigationLink { LeaderboardView() } label: { Label("Leaderboard", systemImage: "list.number") }
                    NavigationLink { PeopleSearchView() } label: { Label("Find a drinker", systemImage: "magnifyingglass") }
                }
                Section("Insights") {
                    NavigationLink { ChartsView() } label: { Label("All charts", systemImage: "chart.bar.xaxis") }
                    NavigationLink { BeerMapView() } label: { Label("Map", systemImage: "map") }
                }
            }
            .navigationTitle("Stats 📊")
        }
    }
}
