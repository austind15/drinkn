import SwiftUI

struct DrinkTypePicker: View {
    @Binding var selection: DrinkType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DrinkType.allCases) { type in
                    Button {
                        selection = type
                    } label: {
                        VStack(spacing: 2) {
                            Text(type.emoji).font(.title2)
                            Text(type.displayName).font(.caption2)
                        }
                        .frame(width: 64, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selection == type
                                      ? Color.orange.opacity(0.25)
                                      : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selection == type ? Color.orange : Color.white.opacity(0.1),
                                        lineWidth: selection == type ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Small inline badge to render on a feed/reason card to show what was drunk.
struct DrinkTypeBadge: View {
    let type: DrinkType

    var body: some View {
        HStack(spacing: 4) {
            Text(type.emoji)
            Text(type.displayName).font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
