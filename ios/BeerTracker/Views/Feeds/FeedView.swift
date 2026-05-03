import SwiftUI
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var beers: [Beer] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var mode: APIClient.FeedMode = .recent

    private let pageSize = 10
    private var loadToken = UUID()

    func reload(groupId: UUID?) async {
        let token = UUID()
        loadToken = token
        isLoading = true
        defer { if loadToken == token { isLoading = false } }
        do {
            let result = try await APIClient.shared.beers(limit: pageSize, offset: 0, mode: mode, groupId: groupId)
            guard loadToken == token else { return }
            self.beers = result
            self.hasMore = result.count == pageSize
            self.error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            guard loadToken == token else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore(groupId: UUID?) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = beers.count
        do {
            let next = try await APIClient.shared.beers(limit: pageSize, offset: offset, mode: mode, groupId: groupId)
            // Append, dedup by id (in case of overlap)
            let existingIds = Set(beers.map(\.id))
            let fresh = next.filter { !existingIds.contains($0.id) }
            self.beers.append(contentsOf: fresh)
            self.hasMore = next.count == pageSize
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setVote(beer: Beer, vote: Int) async {
        do {
            let resp = try await APIClient.shared.vote(beerId: beer.id, vote: vote)
            if let i = beers.firstIndex(where: { $0.id == beer.id }) {
                let original = beers[i]
                beers[i] = Beer(
                    id: original.id,
                    photoURL: original.photoURL,
                    timestamp: original.timestamp,
                    latitude: original.latitude,
                    longitude: original.longitude,
                    locationName: original.locationName,
                    note: original.note,
                    drinkType: original.drinkType,
                    user: original.user,
                    score: resp.score,
                    upvotes: resp.upvotes,
                    downvotes: resp.downvotes,
                    myVote: resp.myVote
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FeedView: View {
    @StateObject private var vm = FeedViewModel()
    @EnvironmentObject var filter: GroupFilterStore
    @State private var selected: Beer?

    private var emptyMessage: String {
        switch vm.mode {
        case .recent: return "Nobody has logged anything yet."
        case .following: return "The people you follow haven't logged anything yet. Try the Social tab to find people."
        case .group:
            if let g = filter.selectedGroup { return "Nobody in \(g.name) has logged anything yet." }
            return "Pick a group above to see their posts."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if vm.mode == .group {
                    HStack {
                        GroupFilterPicker()
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                ScrollView {
                    LazyVStack(spacing: 16) {
                        if vm.isLoading && vm.beers.isEmpty {
                            ProgressView().padding(.top, 60)
                        } else if vm.beers.isEmpty, vm.error == nil {
                            ContentUnavailableView(
                                "Nothing here yet",
                                systemImage: "mug",
                                description: Text(emptyMessage)
                            )
                            .padding(.top, 60)
                        } else {
                            ForEach(vm.beers) { beer in
                                FeedBeerCard(
                                    beer: beer,
                                    onPhotoTap: { selected = beer },
                                    onUpvote: { Task { await tapVote(beer: beer, vote: 1) } },
                                    onDownvote: { Task { await tapVote(beer: beer, vote: -1) } }
                                )
                                .onAppear {
                                    if beer.id == vm.beers.last?.id {
                                        Task { await vm.loadMore(groupId: filter.selectedGroupId) }
                                    }
                                }
                            }

                            if vm.isLoadingMore {
                                ProgressView().padding(.vertical, 16)
                            } else if !vm.hasMore && vm.beers.count > 0 {
                                Text("You've reached the end 🍻")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .refreshable { await vm.reload(groupId: filter.selectedGroupId) }
            }
            .navigationTitle("Feed 🍺")
            .task(id: vm.mode) { await vm.reload(groupId: filter.selectedGroupId) }
            .task(id: filter.selectedGroupId) { await vm.reload(groupId: filter.selectedGroupId) }
            .overlay(alignment: .top) {
                if let err = vm.error, !err.contains("cancelled") {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
            .sheet(item: $selected) { beer in
                BeerDetailSheet(beer: beer).presentationDetents([.large])
            }
        }
    }

    private var modePicker: some View {
        Picker("Feed", selection: $vm.mode) {
            Text("Recent").tag(APIClient.FeedMode.recent)
            Text("Following").tag(APIClient.FeedMode.following)
            Text("Group").tag(APIClient.FeedMode.group)
        }
        .pickerStyle(.segmented)
    }

    private func tapVote(beer: Beer, vote: Int) async {
        let next = (beer.myVote ?? 0) == vote ? 0 : vote
        await vm.setVote(beer: beer, vote: next)
    }
}

private struct FeedBeerCard: View {
    let beer: Beer
    let onPhotoTap: () -> Void
    let onUpvote: () -> Void
    let onDownvote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let user = beer.user {
                NavigationLink {
                    PersonalStatsView(userId: user.id, fallbackName: user.nickname)
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(string: user.profilePictureURL)
                            .frame(width: 36, height: 36).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(user.nickname).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(beer.resolvedDrinkType.emoji).font(.caption)
                            }
                            Text(Format.relative.localizedString(for: beer.timestamp, relativeTo: Date()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: onPhotoTap) {
                RemoteImage(string: beer.photoURL)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                if let loc = beer.locationName, !loc.isEmpty {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = beer.note, !note.isEmpty {
                    Text(note).font(.callout)
                }
                voteRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.05), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var voteRow: some View {
        let myVote = beer.myVote ?? 0
        let score = beer.score ?? 0
        return HStack(spacing: 8) {
            Button(action: onUpvote) {
                Image(systemName: myVote == 1 ? "arrowtriangle.up.fill" : "arrowtriangle.up")
                    .font(.callout.bold())
                    .foregroundStyle(myVote == 1 ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            Text("\(score)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(score > 0 ? .orange : (score < 0 ? .blue : .secondary))
                .frame(minWidth: 24)
            Button(action: onDownvote) {
                Image(systemName: myVote == -1 ? "arrowtriangle.down.fill" : "arrowtriangle.down")
                    .font(.callout.bold())
                    .foregroundStyle(myVote == -1 ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            DrinkTypeBadge(type: beer.resolvedDrinkType)
        }
    }
}
