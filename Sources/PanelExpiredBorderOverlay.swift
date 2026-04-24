import SwiftUI

/// Pulsing red border drawn around an expired pane. Appears the moment the pane's
/// `PanelActivityStore` countdown reaches zero and stays until activity is recorded.
/// The flash is the only animation — no shake, no wash, no sound.
struct PanelExpiredBorderOverlay: View {
    let panelId: UUID
    @ObservedObject private var store = PanelActivityStore.shared
    @State private var pulse: Bool = false

    var body: some View {
        let _ = store.tick
        let expired = store.isExpired(panelId: panelId)

        Group {
            if expired {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.red, lineWidth: 3)
                    .opacity(pulse ? 1.0 : 0.35)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
                    .allowsHitTesting(false)
            }
        }
    }
}
