import SwiftUI

/// Compact selector that lets the user choose "All users" or one of the groups
/// they belong to. Sits at the top of stats screens.
struct GroupFilterPicker: View {
    @EnvironmentObject var filter: GroupFilterStore

    var body: some View {
        Menu {
            Button {
                filter.clear()
            } label: {
                Label("All users 🌍", systemImage: filter.selectedGroupId == nil ? "checkmark" : "")
            }
            if !filter.myGroups.isEmpty {
                Divider()
                ForEach(filter.myGroups) { group in
                    Button {
                        filter.select(group)
                    } label: {
                        Label(group.name, systemImage: filter.selectedGroupId == group.id ? "checkmark" : "")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(filter.selectedGroup?.name ?? "All users")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.orange.opacity(0.5), lineWidth: 1))
        }
        .task {
            if filter.myGroups.isEmpty { await filter.loadGroups() }
        }
    }
}
