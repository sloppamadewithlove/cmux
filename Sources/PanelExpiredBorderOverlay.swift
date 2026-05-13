import SwiftUI

/// Pulsing red border drawn around every pane in a workspace whose countdown has
/// reached zero. Driven by `PanelActivityStore.isExpired(workspaceId:)`, so a
/// single expiry flashes every pane in the workspace at once.
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

/// Legacy per-panel border wrapper kept for source compatibility. Reads the
/// panel-level expired flag directly so existing tests / callers stay working.
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
