import SwiftUI
import Combine

@MainActor
final class PeopleSearchViewModel: ObservableObject {
    @Published var results: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    private var task: Task<Void, Never>?

    func search(_ query: String, groupId: UUID?) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        task = Task { [weak self] in
            // Tiny debounce so we don't fire on every keystroke.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await self?.run(q, groupId: groupId)
        }
    }

    private func run(_ query: String, groupId: UUID?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await APIClient.shared.leaderboard(
                search: query.isEmpty ? nil : query,
                groupId: groupId
            )
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PeopleSearchView: View {
    @StateObject private var vm = PeopleSearchViewModel()
    @EnvironmentObject var filter: GroupFilterStore
    @State private var query: String = ""

    var body: some View {
        List {
            Section {
                HStack { GroupFilterPicker(); Spacer() }
                    .listRowBackground(Color.clear)
            }
            if vm.results.isEmpty, !vm.isLoading {
                ContentUnavailableView(
                    query.isEmpty ? "Search for a drinker" : "No matches",
                    systemImage: "person.2.crop.square.stack",
                    description: Text(query.isEmpty
                        ? "Type a nickname above to find someone."
                        : "Nobody matches “\(query)”.")
                )
            }
            ForEach(vm.results) { entry in
                NavigationLink {
                    PersonalStatsView(userId: entry.userId, fallbackName: entry.nickname)
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(string: entry.profilePictureURL)
                            .frame(width: 40, height: 40).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.nickname).font(.headline)
                            Text("\(entry.totalBeers) beers")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let err = vm.error {
                Text(err).font(.caption.monospaced()).foregroundStyle(.red)
            }
        }
        .navigationTitle("Find a drinker")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Nickname")
        .onChange(of: query) { _, new in vm.search(new, groupId: filter.selectedGroupId) }
        .onChange(of: filter.selectedGroupId) { _, _ in vm.search(query, groupId: filter.selectedGroupId) }
        .task { vm.search("", groupId: filter.selectedGroupId) }
    }
}
