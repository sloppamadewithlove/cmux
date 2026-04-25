import SwiftUI

/// Animated rainbow border drawn around the currently focused pane (MoonDev style).
///
/// Replaces the earlier background-spiral implementation, which required the user
/// to lower Ghostty's `background-opacity` for it to be visible. A border sits on
/// top of the terminal layer at any opacity and instantly communicates which pane
/// is taking input.
///
/// Performance: a single `AngularGradient` rotated by an implicit animation. No
/// per-frame allocations. `.allowsHitTesting(false)` so it never intercepts clicks
/// or scroll events on the terminal underneath.
struct FocusedPaneRainbow: View {
    @State private var rotation: Angle = .degrees(0)

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    var body: some View {
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
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }
            }
            .accessibilityHidden(true)
    }
}
