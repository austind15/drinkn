import Foundation
import Combine

/// Holds the user's currently selected "filter by group" state, plus the list of
/// groups they belong to. Injected as an `@EnvironmentObject` so any stats view
/// can subscribe + react when the filter changes.
@MainActor
final class GroupFilterStore: ObservableObject {
    /// Currently selected group filter. `nil` = all users.
    @Published var selectedGroupId: UUID?
    @Published var myGroups: [BeerGroup] = []
    @Published var error: String?
    @Published var isLoading = false

    var selectedGroup: BeerGroup? {
        guard let id = selectedGroupId else { return nil }
        return myGroups.first(where: { $0.id == id })
    }

    /// Load the current user's groups. Idempotent — safe to call repeatedly.
    func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            myGroups = try await APIClient.shared.myGroups()
            error = nil
            // If our previously-selected group is no longer in our list (e.g.
            // the user left it on another device), reset the filter.
            if let id = selectedGroupId, !myGroups.contains(where: { $0.id == id }) {
                selectedGroupId = nil
            }
        } catch let api as APIError where api.isCancelled {
            // ignore — a newer load is in flight
        } catch {
            self.error = error.localizedDescription
        }
    }

    func select(_ group: BeerGroup?) {
        selectedGroupId = group?.id
    }

    func clear() {
        selectedGroupId = nil
    }
}
