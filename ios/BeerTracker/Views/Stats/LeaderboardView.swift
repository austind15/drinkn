import SwiftUI
import Combine

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var error: String?

    private var loadToken = UUID()

    func load(groupId: UUID?) async {
        let token = UUID()
        loadToken = token
        do {
            let result = try await APIClient.shared.leaderboard(groupId: groupId)
            guard loadToken == token else { return }
            entries = result
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            guard loadToken == token else { return }
            self.error = error.localizedDescription
        }
    }
}

struct LeaderboardView: View {
    @StateObject private var vm = LeaderboardViewModel()
    @EnvironmentObject var filter: GroupFilterStore

    var body: some View {
        List {
            Section {
                HStack {
                    GroupFilterPicker()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            ForEach(Array(vm.entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    PersonalStatsView(userId: entry.userId, fallbackName: entry.nickname)
                } label: {
                    HStack(spacing: 12) {
                        Text("#\(index + 1)").font(.headline.monospacedDigit()).frame(width: 36, alignment: .leading)
                        RemoteImage(string: entry.profilePictureURL)
                            .frame(width: 36, height: 36).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(entry.nickname).font(.headline)
                            Text("\(entry.totalBeers) beers").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Leaderboard 🥇")
        .refreshable { await vm.load(groupId: filter.selectedGroupId) }
        .task(id: filter.selectedGroupId) { await vm.load(groupId: filter.selectedGroupId) }
        .overlay {
            if let err = vm.error { Text(err).foregroundStyle(.red) }
        }
    }
}
