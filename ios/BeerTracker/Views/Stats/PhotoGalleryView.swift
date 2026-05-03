import SwiftUI
import Combine

@MainActor
final class PhotoGalleryViewModel: ObservableObject {
    @Published var beers: [Beer] = []
    @Published var error: String?

    func load(userId: UUID) async {
        do {
            let resp = try await APIClient.shared.userStats(id: userId)
            beers = resp.beers
            error = nil
        } catch let api as APIError where api.isCancelled {
            // ignored
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PhotoGalleryView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = PhotoGalleryViewModel()
    @State private var selected: Beer?

    private let columns = [GridItem(.flexible(), spacing: 4),
                           GridItem(.flexible(), spacing: 4),
                           GridItem(.flexible(), spacing: 4)]

    private var currentUserId: UUID? {
        if case .signedIn(let u) = auth.state { return u.id }
        return nil
    }

    var body: some View {
        ScrollView {
            if vm.beers.isEmpty, vm.error == nil {
                ContentUnavailableView(
                    "Your gallery is empty",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Photos of every beer you log will show up here.")
                )
                .padding(.top, 80)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(vm.beers) { beer in
                    Button { selected = beer } label: {
                        RemoteImage(string: beer.photoURL)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            if let err = vm.error {
                Text(err).font(.caption.monospaced()).foregroundStyle(.red).padding()
            }
        }
        .navigationTitle("My photos 📷")
        .task { if let id = currentUserId, vm.beers.isEmpty { await vm.load(userId: id) } }
        .refreshable { if let id = currentUserId { await vm.load(userId: id) } }
        .sheet(item: $selected) { beer in
            BeerDetailSheet(beer: beer).presentationDetents([.large])
        }
    }
}
