import SwiftUI
import Combine
import Charts

@MainActor
final class PersonalStatsViewModel: ObservableObject {
    @Published var data: APIClient.UserStatsResponse?
    @Published var error: String?
    @Published var isFollowing: Bool = false

    func load(userId: UUID) async {
        do {
            let resp = try await APIClient.shared.userStats(id: userId)
            data = resp
            isFollowing = resp.isFollowing ?? false
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFollow(userId: UUID) async {
        do {
            if isFollowing {
                try await APIClient.shared.unfollow(userId: userId)
                isFollowing = false
            } else {
                try await APIClient.shared.follow(userId: userId)
                isFollowing = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PersonalStatsView: View {
    let userId: UUID
    let fallbackName: String
    @StateObject private var vm = PersonalStatsViewModel()
    @EnvironmentObject var auth: AuthManager
    @State private var showingSettings = false

    private var isMe: Bool {
        if case .signedIn(let me) = auth.state { return me.id == userId }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let resp = vm.data {
                    header(resp.user)
                    followCounts(resp.stats)
                    statsGrid(resp.stats)
                    if let drinks = resp.stats.drinkTypes, drinks.contains(where: { $0.count > 0 }) {
                        drinkBreakdown(drinks)
                    }
                    timelineChart(resp.stats.timeline)
                    photoGrid(resp.beers)
                } else if let err = vm.error {
                    Text(err).foregroundStyle(.red)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding()
        }
        .navigationTitle(vm.data?.user.nickname ?? fallbackName)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .task { await vm.load(userId: userId) }
        .refreshable { await vm.load(userId: userId) }
    }

    private func header(_ user: AppUser) -> some View {
        HStack(spacing: 16) {
            RemoteImage(string: user.profilePictureURL)
                .frame(width: 72, height: 72).clipShape(Circle())
            VStack(alignment: .leading) {
                Text(user.nickname).font(.title2.bold())
                if let created = user.createdAt {
                    Text("Member since \(created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isMe {
                Button {
                    Task { await vm.toggleFollow(userId: userId) }
                } label: {
                    Text(vm.isFollowing ? "Following" : "Follow")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(vm.isFollowing ? .gray : .orange)
            }
        }
    }

    private func followCounts(_ s: PersonalStats) -> some View {
        HStack(spacing: 0) {
            NavigationLink {
                FollowListView(userId: userId, mode: .followers, displayName: vm.data?.user.nickname ?? fallbackName)
            } label: {
                followStat(value: s.followers ?? 0, label: "Followers")
            }
            .buttonStyle(.plain)

            Divider().frame(height: 28)

            NavigationLink {
                FollowListView(userId: userId, mode: .following, displayName: vm.data?.user.nickname ?? fallbackName)
            } label: {
                followStat(value: s.following ?? 0, label: "Following")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func followStat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func statsGrid(_ s: PersonalStats) -> some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCard("Total beers", "\(s.total)", "🍺")
            statCard("Current streak", "\(s.currentStreak) days", "🔥")
            statCard("Longest streak", "\(s.longestStreak) days", "🏆")
            statCard("Most active day",
                     s.mostActiveDayOfWeek.map(Format.dayOfWeekName) ?? "—",
                     "📅")
            statCard("Most active hour",
                     s.mostActiveHour.map(Format.hourLabel) ?? "—",
                     "⏰")
            statCard("Net upvotes", "\(s.netScore ?? 0)", "👍")
        }
    }

    private func statCard(_ title: String, _ value: String, _ emoji: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(emoji).font(.title)
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func drinkBreakdown(_ buckets: [DrinkTypeBucket]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drink mix 🥃").font(.headline)
            Chart(buckets.filter { $0.count > 0 }) { bucket in
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
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func timelineChart(_ timeline: [TimelinePoint]) -> some View {
        VStack(alignment: .leading) {
            Text("Personal timeline").font(.headline)
            if timeline.isEmpty {
                Text("No beers yet — go log one!")
                    .foregroundStyle(.secondary)
            } else {
                Chart(timeline) { p in
                    BarMark(x: .value("Date", p.date), y: .value("Beers", p.count))
                        .foregroundStyle(.orange)
                }
                .chartXAxis(.hidden)
                .frame(height: 180)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func photoGrid(_ beers: [Beer]) -> some View {
        let cols = [GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)]
        return VStack(alignment: .leading) {
            Text("Photos").font(.headline)
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(beers) { beer in
                    RemoteImage(string: beer.photoURL)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

struct MyStatsView: View {
    @EnvironmentObject var auth: AuthManager
    var body: some View {
        Group {
            if case .signedIn(let user) = auth.state {
                PersonalStatsView(userId: user.id, fallbackName: user.nickname)
            } else {
                Text("Sign in to see your stats")
            }
        }
    }
}

// MARK: - Follow list (followers / following)

enum FollowListMode {
    case followers, following

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }
}

@MainActor
final class FollowListViewModel: ObservableObject {
    @Published var users: [SearchUser] = []
    @Published var error: String?
    @Published var isLoading = false

    func load(userId: UUID, mode: FollowListMode) async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .followers:
                users = try await APIClient.shared.followersList(userId: userId)
            case .following:
                users = try await APIClient.shared.followingList(userId: userId)
            }
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleFollow(user: SearchUser) async {
        do {
            if user.isFollowing {
                try await APIClient.shared.unfollow(userId: user.id)
            } else {
                try await APIClient.shared.follow(userId: user.id)
            }
            if let i = users.firstIndex(of: user) {
                users[i] = SearchUser(
                    id: user.id,
                    nickname: user.nickname,
                    profilePictureURL: user.profilePictureURL,
                    isFollowing: !user.isFollowing
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FollowListView: View {
    let userId: UUID
    let mode: FollowListMode
    let displayName: String
    @StateObject private var vm = FollowListViewModel()
    @EnvironmentObject var auth: AuthManager

    private var currentUserId: UUID? {
        if case .signedIn(let u) = auth.state { return u.id }
        return nil
    }

    var body: some View {
        List {
            if vm.users.isEmpty && !vm.isLoading {
                Text(emptyMessage).foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(vm.users) { user in
                    HStack(spacing: 12) {
                        NavigationLink {
                            PersonalStatsView(userId: user.id, fallbackName: user.nickname)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(string: user.profilePictureURL)
                                    .frame(width: 40, height: 40).clipShape(Circle())
                                Text(user.nickname).font(.headline)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if user.id != currentUserId {
                            Button {
                                Task { await vm.toggleFollow(user: user) }
                            } label: {
                                Text(user.isFollowing ? "Following" : "Follow")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(user.isFollowing ? .gray : .orange)
                            .controlSize(.small)
                        }
                    }
                }
            }
            if let err = vm.error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("\(displayName) — \(mode.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(userId: userId, mode: mode) }
        .refreshable { await vm.load(userId: userId, mode: mode) }
    }

    private var emptyMessage: String {
        switch mode {
        case .followers: return "No followers yet."
        case .following: return "Not following anyone yet."
        }
    }
}
