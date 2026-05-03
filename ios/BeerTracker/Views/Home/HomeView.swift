import SwiftUI
import Combine
import CoreLocation
import Charts

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var total: BeerTotal?
    @Published var recentBeers: [Beer] = []
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var stats: TeamStats?
    @Published var errorMessage: String?

    /// Newest in-flight load. Older loads silently discard their results so
    /// quick refreshes / filter changes don't surface "cancelled" errors.
    private var loadToken = UUID()

    func load(groupId: UUID?) async {
        let token = UUID()
        loadToken = token

        async let total = APIClient.shared.beersTotal(groupId: groupId)
        async let beers = APIClient.shared.beers(limit: 10, offset: 0, groupId: groupId)
        async let leaderboard = APIClient.shared.leaderboard(groupId: groupId)
        async let stats = APIClient.shared.teamStats(groupId: groupId)

        do {
            let (t, b, l, s) = try await (total, beers, leaderboard, stats)
            // If a newer load started, drop these results.
            guard loadToken == token else { return }
            self.total = t
            self.recentBeers = b
            self.leaderboard = l
            self.stats = s
            self.errorMessage = nil
        } catch let api as APIError where api.isCancelled {
            // Swallow cancellations — by design, the user kicked off a fresh load.
        } catch {
            guard loadToken == token else { return }
            self.errorMessage = error.localizedDescription
        }
    }
}

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var filter: GroupFilterStore

    private var meId: UUID? {
        if case .signedIn(let u) = auth.state { return u.id }
        return nil
    }

    private var meAvatarURL: String? {
        if case .signedIn(let u) = auth.state { return u.profilePictureURL }
        return nil
    }

    private var meName: String {
        if case .signedIn(let u) = auth.state { return u.nickname }
        return ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BeerBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            GroupFilterPicker()
                            Spacer()
                        }
                        HeroCounterCard(total: vm.total, scopeName: filter.selectedGroup?.name)
                        if let err = vm.errorMessage {
                            Text(err)
                                .font(.caption.monospaced())
                                .foregroundStyle(.white)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        }
                        HighlightPanels(vm: vm)
                        if let stats = vm.stats {
                            DrinkBreakdownPanel(buckets: stats.drinkTypes ?? [])
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
            }
            .refreshable { await vm.load(groupId: filter.selectedGroupId) }
            .navigationTitle("Drink-N 🍺")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let id = meId {
                        NavigationLink {
                            PersonalStatsView(userId: id, fallbackName: meName)
                        } label: {
                            RemoteImage(string: meAvatarURL)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.orange.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
            }
            .task(id: filter.selectedGroupId) {
                await vm.load(groupId: filter.selectedGroupId)
            }
        }
    }
}

/// Subtle warm gradient that ties the dark theme together.
struct BeerBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.05, blue: 0.04),
                Color(red: 0.12, green: 0.08, blue: 0.04)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct HeroCounterCard: View {
    let total: BeerTotal?
    let scopeName: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(Format.grouped(total?.total ?? 0))
                .font(.system(size: 72, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [.orange, Color(red: 1.0, green: 0.55, blue: 0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .orange.opacity(0.4), radius: 16)
            if let scopeName {
                Text("drinks logged in \(scopeName)").font(.headline).foregroundStyle(.white.opacity(0.6))
            } else {
                Text("of 1,000,000 🍺").font(.headline).foregroundStyle(.white.opacity(0.6))
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .padding(.horizontal)
                if total != nil {
                    Text("\(percent)% to a million")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.06), lineWidth: 1))
        )
    }

    private var progress: Double {
        guard let t = total, t.goal > 0 else { return 0 }
        return min(1, Double(t.total) / Double(t.goal))
    }

    private var percent: String {
        String(format: "%.4f", progress * 100)
    }
}

/// Picks 2–3 random highlight panels to render each refresh.
private struct HighlightPanels: View {
    @ObservedObject var vm: HomeViewModel
    @State private var nonce = UUID()

    enum Panel: CaseIterable, Hashable {
        case topThisWeek, mostRecent, todayTotal, weekTotal, longestStreak, latestLocation
    }

    var body: some View {
        let chosen = pickPanels()
        VStack(spacing: 16) {
            ForEach(chosen, id: \.self) { panel in
                panelView(panel)
            }
        }
        .id(nonce)
        .onAppear { nonce = UUID() }
    }

    private func pickPanels() -> [Panel] {
        let all = Panel.allCases.shuffled()
        let n = Bool.random() ? 3 : 2
        return Array(all.prefix(n))
    }

    @ViewBuilder
    private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .topThisWeek: TopDrinkerPanel(entries: vm.leaderboard)
        case .mostRecent: MostRecentPanel(beer: vm.recentBeers.first)
        case .todayTotal: TimedTotalPanel(title: "Today's total 🌞", count: countSince(hours: 24, beers: vm.recentBeers))
        case .weekTotal: TimedTotalPanel(title: "This week 📅", count: vm.stats?.weekTotal ?? 0)
        case .longestStreak: LongestStreakPanel()
        case .latestLocation: LatestLocationPanel(beer: vm.recentBeers.first(where: { $0.coordinate != nil }))
        }
    }

    private func countSince(hours: Int, beers: [Beer]) -> Int {
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        return beers.filter { $0.timestamp > cutoff }.count
    }
}

private struct PanelCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.orange.opacity(0.85))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06), lineWidth: 1))
        )
    }
}

private struct TopDrinkerPanel: View {
    let entries: [LeaderboardEntry]
    var body: some View {
        PanelCard(title: "Top drinker 🥇") {
            if let top = entries.first {
                HStack(spacing: 12) {
                    RemoteImage(string: top.profilePictureURL).frame(width: 44, height: 44).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(top.nickname).font(.headline)
                        Text("\(top.totalBeers) beers").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else { Text("No beers yet — be the first! 🍻") }
        }
    }
}

private struct MostRecentPanel: View {
    let beer: Beer?
    var body: some View {
        PanelCard(title: "Most recent 🍺") {
            if let beer {
                HStack(spacing: 12) {
                    RemoteImage(string: beer.photoURL)
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        HStack(spacing: 6) {
                            Text(beer.user?.nickname ?? "—").font(.headline)
                            Text(beer.resolvedDrinkType.emoji).font(.caption)
                        }
                        Text(Format.relative.localizedString(for: beer.timestamp, relativeTo: Date()))
                            .foregroundStyle(.secondary)
                        if let loc = beer.locationName { Text(loc).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                }
            } else { Text("No beers yet.") }
        }
    }
}

private struct TimedTotalPanel: View {
    let title: String
    let count: Int
    var body: some View {
        PanelCard(title: title) {
            Text("\(count)").font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
            Text("beers logged").foregroundStyle(.secondary)
        }
    }
}

private struct LongestStreakPanel: View {
    var body: some View {
        PanelCard(title: "Longest streak 🔥") {
            Text("Tap Stats to find out").foregroundStyle(.secondary)
        }
    }
}

private struct LatestLocationPanel: View {
    let beer: Beer?
    var body: some View {
        PanelCard(title: "Latest location 📍") {
            if let beer, let coord = beer.coordinate {
                Text(beer.locationName ?? "Somewhere fun")
                Text(String(format: "%.3f, %.3f", coord.latitude, coord.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("No located beers yet")
            }
        }
    }
}

/// Pie chart of the breakdown across drink types (Beer/Wine/Spirits/Cocktail/Cider).
struct DrinkBreakdownPanel: View {
    let buckets: [DrinkTypeBucket]

    private var nonZero: [DrinkTypeBucket] {
        buckets.filter { $0.count > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DRINK MIX 🥃")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.orange.opacity(0.85))

            if nonZero.isEmpty {
                Text("No drinks logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(nonZero) { bucket in
                    SectorMark(
                        angle: .value("Count", bucket.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 1
                    )
                    .foregroundStyle(by: .value("Type", bucket.drinkType?.displayName ?? bucket.type))
                    .annotation(position: .overlay) {
                        if bucket.count > 0 {
                            Text(bucket.drinkType?.emoji ?? "🍺").font(.callout)
                        }
                    }
                }
                .chartLegend(position: .bottom, alignment: .center, spacing: 8)
                .frame(height: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06), lineWidth: 1))
        )
    }
}
