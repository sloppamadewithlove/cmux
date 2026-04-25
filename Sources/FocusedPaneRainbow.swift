import SwiftUI

/// Animated rainbow background for the currently focused pane.
///
/// Mounted *behind* `PanelContentView` in `WorkspaceContentView`'s ZStack so the
/// AppKit-portaled Ghostty surface sits on top. The terminal's
/// `background-opacity` (0.88 by default in `~/.config/ghostty/config`) lets the
/// rainbow show through the terminal's background fill as a slowly rotating
/// wash. Text, cursor, and selections render fully opaque on top, so readability
/// is not affected — only the empty terminal background takes the rainbow tint.
///
/// Performance: a single `AngularGradient` rotated by an implicit animation. No
/// per-frame allocations or images. `.allowsHitTesting(false)` so it never
/// intercepts clicks or scroll events on the terminal.
struct FocusedPaneRainbow: View {
    @State private var rotation: Angle = .degrees(0)

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    private static let cornerRadius: CGFloat = 6
    private static let rotationDuration: Double = 6

    var body: some View {
        let gradient = AngularGradient(
            gradient: Gradient(colors: Self.rainbowStops),
            center: .center,
            angle: rotation
        )

        // Full-pane saturated rainbow fill at full opacity. The visible
        // intensity is governed by the terminal's `background-opacity`: at 0.88
        // the user sees roughly 12% of these colors mixed into the terminal
        // background. Lower `background-opacity` in the ghostty config to make
        // it more vivid.
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(gradient)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(.linear(duration: Self.rotationDuration).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }
            }
    }
}
