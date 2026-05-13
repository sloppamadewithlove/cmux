import SwiftUI

/// Rainbow background for the currently focused pane.
///
/// Mounted *behind* `PanelContentView` in `WorkspaceContentView`'s ZStack so the
/// AppKit-portaled Ghostty surface sits on top. The terminal's
/// `background-opacity` (currently `0.75` in `~/.config/ghostty/config`, raised
/// from a previous `0.88`) lets the rainbow show through the terminal's
/// background fill as a slowly rotating wash. Text, cursor, and selections
/// render fully opaque on top, so readability is not affected — only the empty
/// terminal background takes the rainbow tint.
///
/// Visible rainbow intensity ≈ `(1 − background-opacity)`, so 0.75 gives roughly
/// 25% of these saturated colors mixed into the terminal background. Lower
/// `background-opacity` further to make it more vivid; raise it back toward
/// 1.0 to return to a near-solid terminal background.
///
/// Performance: renders the rainbow spiral once into a cached bitmap and rotates
/// that image, instead of re-rendering a full-pane AngularGradient every frame.
/// Set `cmux.customVisuals.animateRainbow` in UserDefaults to disable/enable the
/// motion. `.allowsHitTesting(false)` so it never intercepts clicks or scroll
/// events on the terminal.
struct FocusedPaneRainbow: View {
    @AppStorage("cmux.customVisuals.animateRainbow") private var animateRainbow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Angle = .degrees(0)

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    private static let cornerRadius: CGFloat = 6
    private static let rotationDuration: Double = 90

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, ceil(hypot(geometry.size.width, geometry.size.height)))

            Group {
                if let image = RainbowSpiralImage.shared {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .rotationEffect(rotation)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else {
                    AngularGradient(
                        gradient: Gradient(colors: Self.rainbowStops),
                        center: .center
                    )
                }
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                updateAnimation()
            }
            .onChange(of: animateRainbow) { _, _ in
                updateAnimation()
            }
            .onChange(of: reduceMotion) { _, _ in
                updateAnimation()
            }
    }

    private func updateAnimation() {
        guard animateRainbow, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                rotation = .degrees(0)
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rotation = .degrees(0)
        }

        withAnimation(.linear(duration: Self.rotationDuration).repeatForever(autoreverses: false)) {
            rotation = .degrees(360)
        }
    }
}
