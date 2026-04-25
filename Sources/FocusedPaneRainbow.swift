import SwiftUI

/// Animated rainbow border drawn around the currently focused pane.
///
/// This is the **selection indicator** for cmux: when a terminal/tab is focused,
/// a thick, slowly-rotating rainbow ring pulses around its content area so the
/// active pane is unmistakable at a glance. Border-only (not a full-pane fill)
/// so terminal text underneath stays fully readable.
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
    private static let outerLineWidth: CGFloat = 4
    private static let innerLineWidth: CGFloat = 1.5

    var body: some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: Self.rainbowStops),
            center: .center,
            angle: rotation
        )

        ZStack {
            // Bold outer ring — the primary "this pane is selected" cue.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(gradient, lineWidth: Self.outerLineWidth)
                .shadow(color: .white.opacity(0.45), radius: 6)
                .shadow(color: .purple.opacity(0.35), radius: 10)

            // Crisp inner accent so the ring reads cleanly against any terminal
            // background color, light or dark.
            RoundedRectangle(cornerRadius: Self.cornerRadius - 1, style: .continuous)
                .strokeBorder(gradient, lineWidth: Self.innerLineWidth)
                .padding(Self.outerLineWidth - 0.5)
                .opacity(0.85)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
        .accessibilityHidden(true)
    }
}
