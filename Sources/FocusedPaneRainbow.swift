import Combine
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
/// Performance: renders the rainbow spiral once into a cached bitmap, then steps
/// the rotation a few degrees every few seconds. That keeps visible motion without
/// a continuous 60Hz SwiftUI animation loop. Set
/// `cmux.customVisuals.animateRainbow` in UserDefaults to disable/enable motion.
/// `.allowsHitTesting(false)` so it never intercepts clicks or scroll events on
/// the terminal.
struct FocusedPaneRainbow: View {
    @AppStorage("cmux.customVisuals.animateRainbow") private var animateRainbow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationDegrees: Double = 0

    private static let rainbowStops: [Color] = [
        .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
    ]

    private static let cornerRadius: CGFloat = 6
    private static let motionStepInterval: TimeInterval = 4
    private static let degreesPerStep: Double = 2
    private static let motionTimer = Timer
        .publish(every: motionStepInterval, on: .main, in: .common)
        .autoconnect()

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
                        .rotationEffect(.degrees(rotationDegrees))
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
                resetMotionIfNeeded()
            }
            .onChange(of: animateRainbow) { _, _ in
                resetMotionIfNeeded()
            }
            .onChange(of: reduceMotion) { _, _ in
                resetMotionIfNeeded()
            }
            .onReceive(Self.motionTimer) { _ in
                guard animateRainbow, !reduceMotion else { return }
                rotationDegrees = (rotationDegrees + Self.degreesPerStep)
                    .truncatingRemainder(dividingBy: 360)
            }
    }

    private func resetMotionIfNeeded() {
        guard !animateRainbow || reduceMotion else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rotationDegrees = 0
        }
    }
}
