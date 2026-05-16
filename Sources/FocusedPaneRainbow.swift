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
/// Performance: renders the rainbow spiral once into a cached bitmap, then hands
/// one slow rotation to Core Animation. There is no per-frame Swift state tick.
/// Set
/// `cmux.customVisuals.animateRainbow` in UserDefaults to disable/enable motion.
/// `.allowsHitTesting(false)` so it never intercepts clicks or scroll events on
/// the terminal.
struct FocusedPaneRainbow: View {
    @AppStorage("cmux.customVisuals.animateRainbow") private var animateRainbow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    private static let cornerRadius: CGFloat = 6
    private static let rotationDuration: TimeInterval = 120

    var body: some View {
        let shouldAnimate = animateRainbow && !reduceMotion

        GeometryReader { geometry in
            let side = max(1, ceil(hypot(geometry.size.width, geometry.size.height)))

            Group {
                if let image = RainbowSpiralImage.shared {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(isRotating ? 360 : 0))
                        .animation(
                            shouldAnimate
                                ? .linear(duration: Self.rotationDuration)
                                    .repeatForever(autoreverses: false)
                                : .default,
                            value: isRotating
                        )
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
                updateMotion(enabled: shouldAnimate)
            }
            .onChange(of: animateRainbow) { _, _ in
                updateMotion(enabled: shouldAnimate)
            }
            .onChange(of: reduceMotion) { _, _ in
                updateMotion(enabled: shouldAnimate)
            }
    }

    private func updateMotion(enabled: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isRotating = false
        }
        guard enabled else { return }
        DispatchQueue.main.async {
            isRotating = true
        }
    }
}
