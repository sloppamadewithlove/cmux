import Foundation
import Combine

/// Process-wide tracker of the last submitted prompt per terminal panel **and per workspace**.
///
/// MoonDev-style behavior: every pane in the same workspace shares one 15-minute
/// countdown. A prompt submission resets the countdown; expiry flashes every pane
/// in that workspace red. The legacy per-panel API is kept so callers that still
/// work in panel terms continue to compile, but visual chrome reads the
/// workspace-scoped values.
///
/// A single 1Hz timer drives `tick`, which is the only `@Published` property views
/// observe. Prompt timestamps live in dictionaries computed against `tick`'s wall
/// clock, so visible HUD instances redraw once per second.
@MainActor
final class PanelActivityStore: ObservableObject {
    static let shared = PanelActivityStore()

    /// Countdown window. 15 minutes per the user's spec.
    let expirationInterval: TimeInterval

    /// Bumped once per second so any view observing this store re-evaluates its
    /// derived remaining-time / expired state. Views should not read this directly —
    /// they should call `remainingTime(...)` / `isExpired(...)`.
    @Published private(set) var tick: UInt64 = 0

    private var lastPromptByPanelId: [UUID: Date] = [:]
    private var lastPromptByWorkspaceId: [UUID: Date] = [:]
    private var lastPublishedPromptByPanelId: [UUID: Date] = [:]
    private var lastPublishedPromptByWorkspaceId: [UUID: Date] = [:]
    /// Reverse mapping so prompt submissions can reset known panels and workspaces.
    private var workspaceForPanel: [UUID: UUID] = [:]
    private var timer: Timer?
    private let publishThrottle: TimeInterval = 1.0

    private init(expirationInterval: TimeInterval = 15 * 60) {
        self.expirationInterval = expirationInterval
        startTimer()
    }

    // MARK: - Workspace-scoped API (preferred)

    func recordPromptSubmission(workspaceId: UUID) {
        let now = Date()
        lastPromptByWorkspaceId[workspaceId] = now
        publishIfNeeded(forWorkspaceId: workspaceId, at: now)
    }

    /// Reset every known workspace/panel when the Claude prompt hook records a
    /// submitted prompt. The hook is global, so it cannot reliably identify the
    /// originating workspace yet.
    func recordPromptSubmission() {
        let now = Date()
        for panelId in workspaceForPanel.keys {
            lastPromptByPanelId[panelId] = now
            lastPublishedPromptByPanelId[panelId] = now
        }
        let workspaceIds = Set(workspaceForPanel.values).union(lastPromptByWorkspaceId.keys)
        for workspaceId in workspaceIds {
            lastPromptByWorkspaceId[workspaceId] = now
            lastPublishedPromptByWorkspaceId[workspaceId] = now
        }
        objectWillChange.send()
    }

    func remainingTime(workspaceId: UUID) -> TimeInterval {
        let last = lastPromptByWorkspaceId[workspaceId] ?? seedFirstWorkspaceObservation(workspaceId: workspaceId)
        let elapsed = Date().timeIntervalSince(last)
        return max(0, expirationInterval - elapsed)
    }

    func isExpired(workspaceId: UUID) -> Bool {
        remainingTime(workspaceId: workspaceId) <= 0
    }

    func forget(workspaceId: UUID) {
        let removedPrompt = lastPromptByWorkspaceId.removeValue(forKey: workspaceId) != nil
        lastPublishedPromptByWorkspaceId.removeValue(forKey: workspaceId)
        guard removedPrompt else { return }
        objectWillChange.send()
    }

    // MARK: - Panel-scoped API (legacy, kept for source compat)

    /// Mark the panel as having a freshly submitted prompt. Resets its countdown
    /// to a full `expirationInterval`. If the panel has been associated with a
    /// workspace via `associate(panelId:workspaceId:)`, the workspace timer is
    /// reset too.
    func recordPromptSubmission(panelId: UUID) {
        let now = Date()
        lastPromptByPanelId[panelId] = now
        publishIfNeeded(forPanelId: panelId, at: now)
        if let workspaceId = workspaceForPanel[panelId] {
            lastPromptByWorkspaceId[workspaceId] = now
            publishIfNeeded(forWorkspaceId: workspaceId, at: now)
        }
    }

    /// Drop the panel from tracking when it is closed, so we don't leak stale entries.
    func forget(panelId: UUID) {
        let removedPanel = lastPromptByPanelId.removeValue(forKey: panelId) != nil
        lastPublishedPromptByPanelId.removeValue(forKey: panelId)
        let removedAssoc = workspaceForPanel.removeValue(forKey: panelId) != nil
        guard removedPanel || removedAssoc else { return }
        objectWillChange.send()
    }

    func remainingTime(panelId: UUID) -> TimeInterval {
        let last = lastPromptByPanelId[panelId] ?? seedFirstPanelObservation(panelId: panelId)
        let elapsed = Date().timeIntervalSince(last)
        return max(0, expirationInterval - elapsed)
    }

    func isExpired(panelId: UUID) -> Bool {
        remainingTime(panelId: panelId) <= 0
    }

    /// Bind a panel to its workspace so prompt submissions can reset the workspace
    /// timer. Safe to call repeatedly; the latest mapping wins.
    func associate(panelId: UUID, workspaceId: UUID) {
        workspaceForPanel[panelId] = workspaceId
    }

    // MARK: - Private

    private func seedFirstPanelObservation(panelId: UUID) -> Date {
        let now = Date()
        lastPromptByPanelId[panelId] = now
        lastPublishedPromptByPanelId[panelId] = now
        return now
    }

    private func seedFirstWorkspaceObservation(workspaceId: UUID) -> Date {
        let now = Date()
        lastPromptByWorkspaceId[workspaceId] = now
        lastPublishedPromptByWorkspaceId[workspaceId] = now
        return now
    }

    private func publishIfNeeded(forPanelId panelId: UUID, at date: Date) {
        guard shouldPublish(lastPublishedPromptByPanelId[panelId], now: date) else { return }
        lastPublishedPromptByPanelId[panelId] = date
        objectWillChange.send()
    }

    private func publishIfNeeded(forWorkspaceId workspaceId: UUID, at date: Date) {
        guard shouldPublish(lastPublishedPromptByWorkspaceId[workspaceId], now: date) else { return }
        lastPublishedPromptByWorkspaceId[workspaceId] = date
        objectWillChange.send()
    }

    private func shouldPublish(_ lastPublished: Date?, now: Date) -> Bool {
        guard let lastPublished else { return true }
        return now.timeIntervalSince(lastPublished) >= publishThrottle
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
