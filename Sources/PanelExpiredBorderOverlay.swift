import SwiftUI

/// Static red border drawn around every pane whose global prompt timer has
/// reached zero.
struct WorkspaceExpiredBorderOverlay: View {
    let workspaceId: UUID
    @ObservedObject private var store = PanelActivityStore.shared

    var body: some View {
        let _ = store.tick
        let expired = store.isExpired(workspaceId: workspaceId)

        Group {
            if expired {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.red, lineWidth: 3)
                    .opacity(0.75)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Legacy per-panel border wrapper kept for source compatibility.
struct PanelExpiredBorderOverlay: View {
    let panelId: UUID
    @ObservedObject private var store = PanelActivityStore.shared

    var body: some View {
        let _ = store.tick
        let expired = store.isExpired(panelId: panelId)

        Group {
            if expired {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.red, lineWidth: 3)
                    .opacity(0.75)
                    .allowsHitTesting(false)
            }
        }
    }
}
