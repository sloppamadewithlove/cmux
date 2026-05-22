import Foundation
import Combine

/// Compatibility store for the older custom-visuals timer API.
///
/// The timer UI was removed from the personal build. Existing focus/cleanup call
/// sites still call through this object, so it stays as a cheap no-op with no
/// scheduled timers and no periodic redraws.
@MainActor
final class PanelActivityStore: ObservableObject {
    static let shared = PanelActivityStore()

    var tick: UInt64 { 0 }

    private var workspaceForPanel: [UUID: UUID] = [:]

    private init() {}

    // MARK: - Workspace-scoped API (preferred)

    func recordActivity(workspaceId: UUID) {
        _ = workspaceId
    }

    func remainingTime(workspaceId: UUID) -> TimeInterval {
        _ = workspaceId
        return .infinity
    }

    func isExpired(workspaceId: UUID) -> Bool {
        false
    }

    func forget(workspaceId: UUID) {
        workspaceForPanel = workspaceForPanel.filter { $0.value != workspaceId }
    }

    // MARK: - Panel-scoped API (legacy, kept for source compat)

    /// Legacy source-compatible hook. Focus/activity is no longer a timer reset
    /// signal; prompt completion is the only reset signal.
    func recordActivity(panelId: UUID) {
        _ = panelId
    }

    /// Drop the panel from tracking when it is closed, so we don't leak stale entries.
    func forget(panelId: UUID) {
        workspaceForPanel.removeValue(forKey: panelId)
    }

    func remainingTime(panelId: UUID) -> TimeInterval {
        _ = panelId
        return .infinity
    }

    func isExpired(panelId: UUID) -> Bool {
        false
    }

    /// Bind a panel to its workspace for source compatibility. The mapping no
    /// longer affects the countdown, which is global across workspaces.
    func associate(panelId: UUID, workspaceId: UUID) {
        workspaceForPanel[panelId] = workspaceId
    }

    // MARK: - Private
}
