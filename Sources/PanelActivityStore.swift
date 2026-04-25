import Foundation
import Combine

/// Process-wide tracker of "last activity" per terminal panel **and per workspace**.
///
/// MoonDev-style behavior: every pane in the same workspace shares one 15-minute
/// countdown. Activity in any pane resets the workspace timer; expiry flashes
/// every pane in that workspace red. The legacy per-panel API is kept so callers
/// that still work in panel terms continue to compile, but visual chrome reads
/// the workspace-scoped values.
///
/// A single 1Hz timer drives `tick`, which is the only `@Published` property views
/// observe. All per-key state lives in dictionaries computed against `tick`'s wall
/// clock, so we get one redraw per second across every visible HUD instance instead
/// of one redraw per state change.
@MainActor
final class PanelActivityStore: ObservableObject {
    static let shared = PanelActivityStore()

    /// Countdown window. 15 minutes per the user's spec.
    let expirationInterval: TimeInterval

    /// Bumped once per second so any view observing this store re-evaluates its
    /// derived remaining-time / expired state. Views should not read this directly —
    /// they should call `remainingTime(...)` / `isExpired(...)`.
    @Published private(set) var tick: UInt64 = 0

    private var lastActivityByPanelId: [UUID: Date] = [:]
    private var lastActivityByWorkspaceId: [UUID: Date] = [:]
    /// Reverse mapping so `recordActivity(panelId:)` can also bump the workspace
    /// when callers route through the panel-level API.
    private var workspaceForPanel: [UUID: UUID] = [:]
    private var timer: Timer?

    private init(expirationInterval: TimeInterval = 15 * 60) {
        self.expirationInterval = expirationInterval
        startTimer()
    }

    // MARK: - Workspace-scoped API (preferred)

    func recordActivity(workspaceId: UUID) {
        lastActivityByWorkspaceId[workspaceId] = Date()
        objectWillChange.send()
    }

    func remainingTime(workspaceId: UUID) -> TimeInterval {
        let last = lastActivityByWorkspaceId[workspaceId] ?? seedFirstWorkspaceObservation(workspaceId: workspaceId)
        let elapsed = Date().timeIntervalSince(last)
        return max(0, expirationInterval - elapsed)
    }

    func isExpired(workspaceId: UUID) -> Bool {
        remainingTime(workspaceId: workspaceId) <= 0
    }

    func forget(workspaceId: UUID) {
        guard lastActivityByWorkspaceId.removeValue(forKey: workspaceId) != nil else { return }
        objectWillChange.send()
    }

    // MARK: - Panel-scoped API (legacy, kept for source compat)

    /// Mark the panel as freshly active. Resets its countdown to a full
    /// `expirationInterval`. If the panel has been associated with a workspace via
    /// `associate(panelId:workspaceId:)`, the workspace timer is reset too.
    func recordActivity(panelId: UUID) {
        lastActivityByPanelId[panelId] = Date()
        if let workspaceId = workspaceForPanel[panelId] {
            lastActivityByWorkspaceId[workspaceId] = Date()
        }
        objectWillChange.send()
    }

    /// Drop the panel from tracking when it is closed, so we don't leak stale entries.
    func forget(panelId: UUID) {
        let removedPanel = lastActivityByPanelId.removeValue(forKey: panelId) != nil
        let removedAssoc = workspaceForPanel.removeValue(forKey: panelId) != nil
        guard removedPanel || removedAssoc else { return }
        objectWillChange.send()
    }

    func remainingTime(panelId: UUID) -> TimeInterval {
        let last = lastActivityByPanelId[panelId] ?? seedFirstPanelObservation(panelId: panelId)
        let elapsed = Date().timeIntervalSince(last)
        return max(0, expirationInterval - elapsed)
    }

    func isExpired(panelId: UUID) -> Bool {
        remainingTime(panelId: panelId) <= 0
    }

    /// Bind a panel to its workspace so the panel-level `recordActivity` also resets
    /// the workspace timer. Safe to call repeatedly; the latest mapping wins.
    func associate(panelId: UUID, workspaceId: UUID) {
        workspaceForPanel[panelId] = workspaceId
    }

    // MARK: - Private

    private func seedFirstPanelObservation(panelId: UUID) -> Date {
        let now = Date()
        lastActivityByPanelId[panelId] = now
        return now
    }

    private func seedFirstWorkspaceObservation(workspaceId: UUID) -> Date {
        let now = Date()
        lastActivityByWorkspaceId[workspaceId] = now
        return now
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tick &+= 1
            }
        }
    }
}
