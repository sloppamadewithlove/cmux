import SwiftUI

/// Top-right per-workspace countdown pill. Always visible. Counts down from 15 min
/// based on `PanelActivityStore`. A submitted prompt resets it.
/// The pill itself never changes color or icon — the *only* visual signal of expiry
/// is the pulsing red border drawn by `WorkspaceExpiredBorderOverlay`.
struct WorkspaceTimerHUD: View {
    let workspaceId: UUID
    @ObservedObject private var store = PanelActivityStore.shared

    var body: some View {
        // Reading `store.tick` here forces the view to re-evaluate every second.
        let _ = store.tick
        let remaining = store.remainingTime(workspaceId: workspaceId)
        let expired = remaining <= 0

        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
            Text(formatted(remaining))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(expired ? Color.red : Color.primary.opacity(0.9))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(expired ? Color.red.opacity(0.7) : .white.opacity(0.18), lineWidth: 0.5)
        )
        .padding(.trailing, 8)
        .allowsHitTesting(false)
        .accessibilityLabel(Text(verbatim: "Workspace prompt timer"))
        .accessibilityValue(Text(verbatim: formatted(remaining)))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Legacy per-panel timer wrapper kept so any callers still passing a panelId compile.
/// Resolves the workspace via `PanelActivityStore`'s reverse map; if no workspace is
/// associated, falls back to the panel-level remaining time so the legacy view still
/// renders something coherent in tests.
struct PanelTimerHUD: View {
    let panelId: UUID
    @ObservedObject private var store = PanelActivityStore.shared

    var body: some View {
        let _ = store.tick
        let remaining = store.remainingTime(panelId: panelId)

        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .medium))
            Text(formatted(remaining))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .padding(.top, 32)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
