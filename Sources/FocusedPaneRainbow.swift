import SwiftUI

/// Slow-rotating rainbow spiral painted as the background of the focused pane so the
/// user can instantly tell which terminal they are typing into. 10% opacity, GPU-cheap
/// (single CGImage rotated by Core Animation), non-interactive.
///
/// To actually read as a background: set `background-opacity` below 1.0 in
/// `~/.config/ghostty/config` so the terminal surface is translucent and this layer
/// shows through.
struct FocusedPaneRainbow: View {
    @State private var angle: Angle = .zero

    var body: some View {
        GeometryReader { geo in
            // Square covering the pane's diagonal so the spiral fills every corner at
            // every rotation angle without exposing transparent edges.
            let diameter = hypot(geo.size.width, geo.size.height) * 1.2

            Group {
                if let cgImage = RainbowSpiralImage.shared {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diameter, height: diameter)
                        .rotationEffect(angle)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .opacity(0.10)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) {
                    angle = .degrees(360)
                }
            }
        }
    }
}
