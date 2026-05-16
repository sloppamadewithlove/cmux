import Foundation
import Combine

/// Process-wide prompt timer shared by every workspace.
///
/// The countdown is global, not per panel or per project. Switching panes,
/// tabs, or workspaces must not reset it. The only reset signal is a completed
/// prompt appended to `~/.cmux/prompts.jsonl`, surfaced by `GlobalEditCounter`.
/// The panel/workspace-shaped API is kept so existing call sites continue to
/// compile, but all visual chrome reads the same global countdown.
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

    private var lastPromptAt: Date
    private var observedPromptLifetime: Int
    private var workspaceForPanel: [UUID: UUID] = [:]
    private var timer: Timer?
    private var promptSubscription: AnyCancellable?

    private init(expirationInterval: TimeInterval = 15 * 60) {
        self.expirationInterval = expirationInterval
        let counter = GlobalEditCounter.shared
        self.lastPromptAt = counter.lastEntryAt ?? Date()
        self.observedPromptLifetime = counter.lifetime
        startTimer()
        promptSubscription = counter.$lifetime
            .combineLatest(counter.$lastEntryAt)
            .sink { [weak self] lifetime, lastEntryAt in
                Task { @MainActor in
                    self?.applyPromptState(lifetime: lifetime, lastEntryAt: lastEntryAt)
                }
            }
    }

    // MARK: - Workspace-scoped API (preferred)

    func recordActivity(workspaceId: UUID) {
        _ = workspaceId
    }

    func remainingTime(workspaceId: UUID) -> TimeInterval {
        _ = workspaceId
        return globalRemainingTime()
    }

    func isExpired(workspaceId: UUID) -> Bool {
        remainingTime(workspaceId: workspaceId) <= 0
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
        return globalRemainingTime()
    }

    func isExpired(panelId: UUID) -> Bool {
        remainingTime(panelId: panelId) <= 0
    }

    /// Bind a panel to its workspace for source compatibility. The mapping no
    /// longer affects the countdown, which is global across workspaces.
    func associate(panelId: UUID, workspaceId: UUID) {
        workspaceForPanel[panelId] = workspaceId
    }

    // MARK: - Private

    private func globalRemainingTime() -> TimeInterval {
        let elapsed = Date().timeIntervalSince(lastPromptAt)
        return max(0, expirationInterval - elapsed)
    }

    private func applyPromptState(lifetime: Int, lastEntryAt: Date?) {
        defer {
            observedPromptLifetime = max(observedPromptLifetime, lifetime)
        }

        if lifetime > observedPromptLifetime {
            lastPromptAt = lastEntryAt ?? Date()
            objectWillChange.send()
            return
        }

        guard let lastEntryAt, lastEntryAt > lastPromptAt else { return }
        lastPromptAt = lastEntryAt
        objectWillChange.send()
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
