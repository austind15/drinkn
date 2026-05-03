import SwiftUI
import Combine
import MapKit

@MainActor
final class BeerMapViewModel: ObservableObject {
    @Published var beers: [Beer] = []
    @Published var error: String?

    private var loadToken = UUID()

    func load(groupId: UUID?) async {
        let token = UUID()
        loadToken = token
        do {
            let result = try await APIClient.shared.beersMap(groupId: groupId)
            guard loadToken == token else { return }
            beers = result
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            guard loadToken == token else { return }
            self.error = error.localizedDescription
        }
    }
}

struct BeerMapView: View {
    @StateObject private var vm = BeerMapViewModel()
    @EnvironmentObject var filter: GroupFilterStore
    @State private var selected: Beer?
    @State private var position: MapCameraPosition = .automatic

    private var locatedBeers: [Beer] {
        vm.beers.filter { $0.coordinate != nil }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: Binding<UUID?>(
                get: { selected?.id },
                set: { id in selected = vm.beers.first(where: { $0.id == id }) }
            )) {
                ForEach(locatedBeers) { beer in
                    if let coord = beer.coordinate {
                        Annotation(
                            beer.locationName ?? beer.user?.nickname ?? "🍺",
                            coordinate: coord
                        ) {
                            BeerPin(beer: beer)
                                .onTapGesture { selected = beer }
                        }
                        .tag(beer.id)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))

            VStack(spacing: 8) {
                HStack { GroupFilterPicker(); Spacer() }
                    .padding(.horizontal)
                statusBanner
            }
            .padding(.top, 4)
        }
        .navigationTitle("Map")
        .task(id: filter.selectedGroupId) {
            await vm.load(groupId: filter.selectedGroupId)
            recenter()
        }
        .refreshable {
            await vm.load(groupId: filter.selectedGroupId)
            recenter()
        }
        .sheet(item: $selected) { beer in
            BeerDetailSheet(beer: beer)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let err = vm.error {
            mapBanner(err, color: .red.opacity(0.85))
        } else if !vm.beers.isEmpty && locatedBeers.isEmpty {
            mapBanner("No beers have locations yet — tap \"Use my location\" when logging.",
                      color: .orange.opacity(0.85))
        }
    }

    private func mapBanner(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color, in: Capsule())
            .padding(.top, 8)
    }

    private func recenter() {
        let coords = locatedBeers.compactMap(\.coordinate)
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.05, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.05, (lons.max()! - lons.min()!) * 1.4)
        )
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

/// Always-visible pin: orange disc with a 🍺 inside. Stays a constant size
/// regardless of zoom level so pins are visible even on the world map.
private struct BeerPin: View {
    let beer: Beer

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.5, blue: 0)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Text("🍺").font(.system(size: 16))
        }
    }
}

struct BeerDetailSheet: View {
    let beer: Beer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RemoteImage(string: beer.photoURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    if let user = beer.user {
                        Label(user.nickname, systemImage: "person.fill")
                    }
                    Spacer()
                    DrinkTypeBadge(type: beer.resolvedDrinkType)
                }
                Label(beer.timestamp.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "clock")
                if let loc = beer.locationName {
                    Label(loc, systemImage: "mappin.and.ellipse")
                }
                if let note = beer.note {
                    Text(note).font(.body)
                }
            }
            .padding()
        }
    }
}
