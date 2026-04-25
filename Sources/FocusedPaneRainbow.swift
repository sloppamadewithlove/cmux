import SwiftUI

/// Full-pane rainbow spiral overlay drawn on top of the currently focused pane.
///
/// Replaces the earlier outline-only border at user request: the previous version
/// only outlined the focused pane, which was easy to miss when several tabs were
/// open at once. This version covers the entire pane with a slowly rotating
/// rainbow spiral at low opacity, blended additively so terminal text underneath
/// stays readable while the focused pane becomes unmistakable at a glance.
///
/// Performance: the spiral itself is a single `CGImage` rendered once via
/// `RainbowSpiralImage.shared` and reused across all panes. The animation is
/// just a rotation of that image (GPU-cheap, no per-frame redraw). A second
/// `strokeBorder` layer adds a crisp edge accent on top of the fill.
/// `.allowsHitTesting(false)` so it never intercepts clicks or scrolls on the
/// terminal layer beneath.
struct FocusedPaneRainbow: View {
    @State private var rotation: Angle = .degrees(0)

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    var body: some View {
        ZStack {
            spiralFill
            edgeAccent
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var spiralFill: some View {
        if let cgImage = RainbowSpiralImage.shared {
            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height) * 1.5
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .rotationEffect(rotation)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .blendMode(.plusLighter)
                    .opacity(0.22)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            // Fallback if CGImage construction failed: an angular gradient still
            // identifies the focused pane, just without the spiral structure.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: Self.rainbowStops),
                        center: .center,
                        angle: rotation
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.22)
        }
    }

    private var edgeAccent: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: Self.rainbowStops),
                    center: .center,
                    angle: rotation
                ),
                lineWidth: 2.5
            )
            .shadow(color: .white.opacity(0.18), radius: 4)
    }
}
