import SwiftUI

/// Draggable workspace countdown timer that the user can position anywhere inside
/// the cmux window. Replaces the fixed top-trailing `WorkspaceTimerHUD` placement
/// so a user who wants the timer prominently visible can park it wherever it sits
/// best in their layout.
///
/// Position is persisted globally (not per-workspace) via `@AppStorage`, so the
/// timer stays where you parked it across workspace switches and app restarts.
/// Content is per-workspace — it always shows the countdown for whichever workspace
/// the overlay is rendered in.
///
/// To escape the cmux window bounds entirely (i.e. drag the timer onto another
/// monitor), this overlay would need to migrate to a floating `NSPanel`. The
/// current implementation is window-local for simplicity.
struct FloatingTimerOverlay: View {
    let workspaceId: UUID

    @AppStorage(Self.storedXKey) private var storedX: Double = Self.defaultX
    @AppStorage(Self.storedYKey) private var storedY: Double = Self.defaultY
    @GestureState private var dragTranslation: CGSize = .zero
    @ObservedObject private var store = PanelActivityStore.shared

    // v3 keys — bumped so any prior off-screen or portal-covered drag position
    // from earlier builds is forgotten and the timer reappears in the tab-bar area.
    private static let storedXKey = "floatingTimerOverlay.v3.x"
    private static let storedYKey = "floatingTimerOverlay.v3.y"
    private static let defaultX: Double = 10
    private static let defaultY: Double = 8
    private static let pillSize = CGSize(width: 110, height: 32)

    var body: some View {
        GeometryReader { proxy in
            timerPill
                .frame(width: Self.pillSize.width, height: Self.pillSize.height)
                .offset(
                    x: clampedX(in: proxy.size) + dragTranslation.width,
                    y: clampedY(in: proxy.size) + dragTranslation.height
                )
                .gesture(dragGesture(in: proxy.size))
        }
        .allowsHitTesting(true)
    }

    private var timerPill: some View {
        let _ = store.tick
        let remaining = store.remainingTime(workspaceId: workspaceId)
        let expired = remaining <= 0

        return HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
            Text(formatted(remaining))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(expired ? Color.red : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(
                expired ? Color.red.opacity(0.85) : Color.white.opacity(0.18),
                lineWidth: expired ? 1.2 : 0.5
            )
        )
        .shadow(radius: 6, y: 2)
        .contentShape(Capsule())
        .help(Text(verbatim: "Drag to reposition. Resets when a prompt is submitted."))
        .accessibilityLabel(Text(verbatim: "Workspace prompt timer"))
        .accessibilityValue(Text(verbatim: formatted(remaining)))
    }

    private func dragGesture(in containerSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let newX = clampedX(in: containerSize) + value.translation.width
                let newY = clampedY(in: containerSize) + value.translation.height
                storedX = clamp(newX, min: 0, max: maxX(in: containerSize))
                storedY = clamp(newY, min: 0, max: maxY(in: containerSize))
            }
    }

    private func clampedX(in size: CGSize) -> Double {
        clamp(storedX, min: 0, max: maxX(in: size))
    }

    private func clampedY(in size: CGSize) -> Double {
        clamp(storedY, min: 0, max: maxY(in: size))
    }

    private func maxX(in size: CGSize) -> Double {
        max(0, Double(size.width) - Double(Self.pillSize.width))
    }

    private func maxY(in size: CGSize) -> Double {
        max(0, Double(size.height) - Double(Self.pillSize.height))
    }

    private func clamp(_ value: Double, min lo: Double, max hi: Double) -> Double {
        Swift.max(lo, Swift.min(hi, value))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
