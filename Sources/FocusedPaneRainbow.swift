import SwiftUI

/// Full-pane rainbow overlay drawn on top of the currently focused pane.
///
/// This is the **selection indicator** for cmux: when a terminal/tab is focused,
/// a slowly-rotating rainbow gradient fills the entire pane content area at low
/// opacity so the active pane is unmistakable at a glance, while terminal text
/// underneath remains readable.
///
/// Performance: a single `AngularGradient` rotated by an implicit animation. No
/// per-frame allocations or images. `.allowsHitTesting(false)` so it never
/// intercepts clicks or scroll events on the terminal underneath.
struct FocusedPaneRainbow: View {
    @State private var rotation: Angle = .degrees(0)

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    private static let cornerRadius: CGFloat = 6
    private static let fillOpacity: Double = 0.18
    private static let borderOpacity: Double = 0.85
    private static let borderWidth: CGFloat = 1.5
    private static let rotationDuration: Double = 6

    var body: some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: Self.rainbowStops),
            center: .center,
            angle: rotation
        )

        ZStack {
            // Full-pane semi-transparent rainbow fill — primary selection cue.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(gradient)
                .opacity(Self.fillOpacity)

            // Crisp accent border so the pane edge stays defined against any
            // terminal background, light or dark.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(gradient, lineWidth: Self.borderWidth)
                .opacity(Self.borderOpacity)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: Self.rotationDuration).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
        .accessibilityHidden(true)
    }
}
