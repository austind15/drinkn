import SwiftUI

/// Lightweight async image wrapper around AsyncImage with a placeholder.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                Color.gray.opacity(0.15)
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Color.gray.opacity(0.2)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            @unknown default:
                Color.gray.opacity(0.15)
            }
        }
    }
}

extension RemoteImage {
    init(string: String?, contentMode: ContentMode = .fill) {
        self.url = string.flatMap(URL.init(string:))
        self.contentMode = contentMode
    }
}
