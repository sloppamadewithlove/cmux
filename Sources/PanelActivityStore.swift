import Foundation
import Combine

/// Process-wide tracker of "last activity" per terminal panel.
///
/// A panel's countdown starts at `expirationInterval` (default 15 min) the first time
/// the store sees its id. Every call to `recordActivity(panelId:)` resets the panel
/// back to a full window. Once the remaining time hits zero, `isExpired(panelId:)`
/// stays true until activity is recorded again — that is the signal `PanelExpiredBorderOverlay`
/// uses to flash the pane red.
///
/// A single 1Hz timer drives `tick`, which is the only `@Published` property views observe.
/// All per-panel state lives in `lastActivityByPanelId` and is computed against `tick`'s
/// wall clock, so we get one redraw per second across every visible timer HUD instead of
/// one redraw per panel per state change.
@MainActor
final class PanelActivityStore: ObservableObject {
    static let shared = PanelActivityStore()

    /// Countdown window per panel. 15 minutes per the user's spec.
    let expirationInterval: TimeInterval

    /// Bumped once per second so any view observing this store re-evaluates its derived
    /// remaining-time / expired state. Views should not read this directly — they should
    /// call `remainingTime(panelId:)` / `isExpired(panelId:)`.
    @Published private(set) var tick: UInt64 = 0

    private var lastActivityByPanelId: [UUID: Date] = [:]
    private var timer: Timer?

    private init(expirationInterval: TimeInterval = 15 * 60) {
        self.expirationInterval = expirationInterval
        startTimer()
    }

    /// Mark the panel as freshly active. Resets its countdown to a full `expirationInterval`
    /// and clears any "expired" flashing state.
    func recordActivity(panelId: UUID) {
        lastActivityByPanelId[panelId] = Date()
        objectWillChange.send()
    }

    /// Drop the panel from tracking when it is closed, so we don't leak stale entries.
    func forget(panelId: UUID) {
        guard lastActivityByPanelId.removeValue(forKey: panelId) != nil else { return }
        objectWillChange.send()
    }

    /// Seconds remaining in the panel's countdown, clamped to [0, expirationInterval].
    /// Returns `expirationInterval` for panels we've never seen — first observation seeds
    /// the timer at the full window without requiring an explicit `recordActivity` call.
    func remainingTime(panelId: UUID) -> TimeInterval {
        let last = lastActivityByPanelId[panelId] ?? seedFirstObservation(panelId: panelId)
        let elapsed = Date().timeIntervalSince(last)
        return max(0, expirationInterval - elapsed)
    }

    func isExpired(panelId: UUID) -> Bool {
        remainingTime(panelId: panelId) <= 0
    }

    private func seedFirstObservation(panelId: UUID) -> Date {
        let now = Date()
        lastActivityByPanelId[panelId] = now
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
