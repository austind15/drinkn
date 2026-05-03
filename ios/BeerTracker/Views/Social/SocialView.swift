import SwiftUI
import Combine

@MainActor
final class SocialViewModel: ObservableObject {
    @Published var searchResults: [SearchUser] = []
    @Published var discoverGroups: [BeerGroup] = []
    @Published var incomingInvites: [GroupInvite] = []
    @Published var query: String = ""
    @Published var error: String?
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    func loadAll() async {
        async let invites = APIClient.shared.incomingInvites()
        async let discover = APIClient.shared.discoverGroups()
        async let users = APIClient.shared.searchUsers(query: "")
        do {
            self.incomingInvites = try await invites
            self.discoverGroups = try await discover
            self.searchResults = try await users
            self.error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }

    func runSearch(_ q: String) {
        searchTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await self?.runSearchNow(trimmed)
        }
    }

    private func runSearchNow(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            async let users = APIClient.shared.searchUsers(query: q)
            async let groups = APIClient.shared.discoverGroups(search: q.isEmpty ? nil : q)
            self.searchResults = try await users
            self.discoverGroups = try await groups
            self.error = nil
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
            // Optimistically update local list
            if let i = searchResults.firstIndex(of: user) {
                searchResults[i] = SearchUser(
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

    func acceptInvite(_ invite: GroupInvite, filter: GroupFilterStore) async {
        do {
            try await APIClient.shared.acceptInvite(id: invite.id)
            incomingInvites.removeAll { $0.id == invite.id }
            await filter.loadGroups()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func declineInvite(_ invite: GroupInvite) async {
        do {
            try await APIClient.shared.declineInvite(id: invite.id)
            incomingInvites.removeAll { $0.id == invite.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SocialView: View {
    @StateObject private var vm = SocialViewModel()
    @EnvironmentObject var filter: GroupFilterStore
    @State private var showingCreateGroup = false

    var body: some View {
        NavigationStack {
            List {
                if !vm.incomingInvites.isEmpty {
                    Section("Pending invites 📬") {
                        ForEach(vm.incomingInvites) { invite in
                            invitedRow(invite)
                        }
                    }
                }

                Section("Your groups 👥") {
                    if filter.myGroups.isEmpty {
                        Text("You're not in any groups yet.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(filter.myGroups) { group in
                            NavigationLink {
                                GroupDetailView(groupId: group.id, fallbackName: group.name)
                            } label: {
                                myGroupRow(group)
                            }
                        }
                    }
                    Button {
                        showingCreateGroup = true
                    } label: {
                        Label("Create a new group", systemImage: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Discover groups 🔍") {
                    if vm.discoverGroups.isEmpty {
                        Text("No groups to show.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(vm.discoverGroups) { group in
                            NavigationLink {
                                GroupDetailView(groupId: group.id, fallbackName: group.name)
                            } label: {
                                discoverGroupRow(group)
                            }
                        }
                    }
                }

                Section("People 🍻") {
                    if vm.searchResults.isEmpty {
                        Text(vm.query.isEmpty ? "No users yet." : "No matches.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(vm.searchResults) { user in
                            personRow(user)
                        }
                    }
                }

                if let err = vm.error {
                    Section {
                        Text(err).font(.caption.monospaced()).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Social")
            .searchable(text: $vm.query, prompt: "Search people or groups")
            .onChange(of: vm.query) { _, new in vm.runSearch(new) }
            .refreshable {
                async let a: () = vm.loadAll()
                async let b: () = filter.loadGroups()
                _ = await (a, b)
            }
            .task {
                await filter.loadGroups()
                await vm.loadAll()
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupSheet(onCreated: { newGroup in
                    Task {
                        await filter.loadGroups()
                        showingCreateGroup = false
                        filter.select(newGroup)
                    }
                })
            }
        }
    }

    @ViewBuilder
    private func invitedRow(_ invite: GroupInvite) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invite.group.name).font(.headline)
                Text("Invited by \(invite.invitedByUser.nickname)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Accept") {
                Task { await vm.acceptInvite(invite, filter: filter) }
            }
            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            Button("Decline") {
                Task { await vm.declineInvite(invite) }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func myGroupRow(_ group: BeerGroup) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.headline)
                HStack(spacing: 8) {
                    if group.isAdmin {
                        Text("Admin").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(0.25), in: Capsule())
                    }
                    if let count = group.memberCount {
                        Text("\(count) member\(count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
    }

    private func discoverGroupRow(_ group: BeerGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name).font(.headline)
            if let desc = group.description, !desc.isEmpty {
                Text(desc).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func personRow(_ user: SearchUser) -> some View {
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

// MARK: - Create Group sheet

private struct CreateGroupSheet: View {
    let onCreated: (BeerGroup) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Office Drinkers", text: $name)
                }
                Section("Description (optional)") {
                    TextField("What's this group about?", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                if let err = error {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Creating…" : "Create") { create() }
                        .disabled(isSubmitting || name.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }

    private func create() {
        isSubmitting = true
        error = nil
        Task {
            do {
                let group = try await APIClient.shared.createGroup(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description
                )
                onCreated(group)
            } catch {
                self.error = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

// MARK: - Group detail view (members, invite, leave, promote)

@MainActor
final class GroupDetailViewModel: ObservableObject {
    @Published var detail: APIClient.GroupDetailResponse?
    @Published var error: String?
    @Published var isLoading = false

    func load(id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.groupDetail(id: id)
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct GroupDetailView: View {
    let groupId: UUID
    let fallbackName: String

    @StateObject private var vm = GroupDetailViewModel()
    @EnvironmentObject var filter: GroupFilterStore
    @EnvironmentObject var auth: AuthManager
    @State private var showingInviteSheet = false
    @State private var promotingMember: GroupMember?

    private var currentUserId: UUID? {
        if case .signedIn(let u) = auth.state { return u.id }
        return nil
    }

    private var currentUserIsAdmin: Bool {
        guard let detail = vm.detail else { return false }
        return detail.members.first(where: { $0.id == currentUserId })?.isAdmin ?? false
    }

    var body: some View {
        List {
            if let detail = vm.detail {
                Section {
                    if let desc = detail.group.description, !desc.isEmpty {
                        Text(desc)
                    }
                    HStack {
                        Text("\(detail.members.count) member\(detail.members.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Filter stats by this group") {
                            filter.select(detail.group)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered).tint(.orange)
                    }
                }

                Section {
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Label("Invite people", systemImage: "person.badge.plus")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Members") {
                    ForEach(detail.members) { member in
                        Button {
                            if currentUserIsAdmin && !member.isAdmin && member.id != currentUserId {
                                promotingMember = member
                            }
                        } label: {
                            HStack(spacing: 12) {
                                RemoteImage(string: member.profilePictureURL)
                                    .frame(width: 40, height: 40).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.nickname).font(.headline)
                                    if member.isAdmin {
                                        Text("Admin").font(.caption2.bold())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if currentUserIsAdmin && !member.isAdmin && member.id != currentUserId {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button("Leave group", role: .destructive) {
                        Task {
                            try? await APIClient.shared.leaveGroup(id: groupId)
                            await filter.loadGroups()
                        }
                    }
                }
            } else if let err = vm.error {
                Text(err).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(vm.detail?.group.name ?? fallbackName)
        .task { await vm.load(id: groupId) }
        .refreshable { await vm.load(id: groupId) }
        .sheet(isPresented: $showingInviteSheet) {
            InvitePeopleSheet(groupId: groupId, onInvited: {
                Task { await vm.load(id: groupId) }
            })
        }
        .confirmationDialog("Promote to admin?", isPresented: Binding(
            get: { promotingMember != nil },
            set: { if !$0 { promotingMember = nil } }
        )) {
            Button("Make admin", role: .destructive) {
                if let m = promotingMember { promote(m) }
            }
            Button("Cancel", role: .cancel) { promotingMember = nil }
        } message: {
            Text("\(promotingMember?.nickname ?? "") will be able to manage members.")
        }
    }

    private func promote(_ member: GroupMember) {
        Task {
            do {
                try await APIClient.shared.promoteMember(groupId: groupId, memberId: member.id)
                await vm.load(id: groupId)
            } catch {
                vm.error = error.localizedDescription
            }
            promotingMember = nil
        }
    }
}

// MARK: - Invite People sheet (search-as-you-type)

@MainActor
private final class InvitePeopleViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [APIClient.InviteSearchUser] = []
    @Published var error: String?
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?
    let groupId: UUID

    init(groupId: UUID) { self.groupId = groupId }

    func onQueryChange(_ q: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            await self?.search(q)
        }
    }

    private func search(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await APIClient.shared.inviteSearch(groupId: groupId, query: q)
            error = nil
        } catch let api as APIError where api.isCancelled { }
        catch { self.error = error.localizedDescription }
    }

    func invite(user: APIClient.InviteSearchUser) async {
        do {
            try await APIClient.shared.inviteToGroup(groupId: groupId, userId: user.id)
            if let i = results.firstIndex(of: user) {
                results[i] = APIClient.InviteSearchUser(
                    id: user.id, nickname: user.nickname,
                    profilePictureURL: user.profilePictureURL, invitePending: true
                )
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InvitePeopleSheet: View {
    let groupId: UUID
    let onInvited: () -> Void
    @StateObject private var vm: InvitePeopleViewModel
    @Environment(\.dismiss) var dismiss

    init(groupId: UUID, onInvited: @escaping () -> Void) {
        self.groupId = groupId
        self.onInvited = onInvited
        _vm = StateObject(wrappedValue: InvitePeopleViewModel(groupId: groupId))
    }

    var body: some View {
        NavigationStack {
            List {
                if let err = vm.error {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                if vm.results.isEmpty && !vm.isSearching {
                    Text(vm.query.isEmpty ? "Start typing to search for people." : "No matches.")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(vm.results) { user in
                        HStack(spacing: 12) {
                            RemoteImage(string: user.profilePictureURL)
                                .frame(width: 36, height: 36).clipShape(Circle())
                            Text(user.nickname).font(.headline)
                            Spacer()
                            if user.invitePending {
                                Text("Invited").font(.caption.bold()).foregroundStyle(.secondary)
                            } else {
                                Button("Invite") {
                                    Task { await vm.invite(user: user); onInvited() }
                                }
                                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Invite People")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by username")
            .onChange(of: vm.query) { _, new in vm.onQueryChange(new) }
            .task { await Task.yield(); vm.onQueryChange("") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

