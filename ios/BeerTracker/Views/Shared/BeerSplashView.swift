import SwiftUI

/// Splash shown while the app is bootstrapping. Beer emojis pop in at random
/// positions and rotations, rapidly — the opposite of a fade-in.
struct BeerSplashView: View {
    @State private var splats: [Splat] = []

    private struct Splat: Identifiable {
        let id = UUID()
        let position: CGPoint
        let rotation: Double
        let size: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.10, green: 0.05, blue: 0.0)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ForEach(splats) { splat in
                    Text("🍺")
                        .font(.system(size: splat.size))
                        .rotationEffect(.degrees(splat.rotation))
                        .position(splat.position)
                        .transition(.identity) // pop in instantly, no fade
                }

                VStack(spacing: 8) {
                    Text("Drink-N")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .orange],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .shadow(color: .orange.opacity(0.6), radius: 18)
                    Text("Towards 1,000,000 🍺")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .task { await spawnSplats(in: geo.size) }
        }
    }

    private func spawnSplats(in size: CGSize) async {
        for _ in 0..<400 {
            let splat = Splat(
                position: CGPoint(
                    x: .random(in: 0...size.width),
                    y: .random(in: 0...size.height)
                ),
                rotation: .random(in: -60...60),
                size: .random(in: 24...64)
            )
            splats.append(splat)
            try? await Task.sleep(nanoseconds: 25_000_000) // 25 ms tick
        }
    }
}
