import SwiftUI

/// Top-right floating pill showing **successful prompts today** across every
/// project — one "prompt" = one round trip (user message → assistant response).
/// Resets at local midnight via `GlobalEditCounter`'s date filter.
///
/// Renamed from the pencil HUD to a number-first display at user request. The
/// small "today" label makes the daily-reset semantics legible at a glance.
struct GlobalEditCounterHUD: View {
    @ObservedObject private var counter = GlobalEditCounter.shared
    @State private var showingPopover: Bool = false

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            HStack(spacing: 6) {
                Text("\(counter.today)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(counter.today)))
                Text(verbatim: "pts")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)                // CustomUpdateHUD is hidden in this fork
        .padding(.trailing, 8)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            PromptCounterPopover(
                today: counter.today,
                lifetime: counter.lifetime,
                lastEntryAt: counter.lastEntryAt,
                logPath: counter.logFileURL.path
            )
        }
        .help(Text(verbatim: "Successful prompts today: \(counter.today) · lifetime \(counter.lifetime). Resets at 00:00 local."))
        .animation(.spring(duration: 0.3), value: counter.today)
    }
}

private struct PromptCounterPopover: View {
    let today: Int
    let lifetime: Int
    let lastEntryAt: Date?
    let logPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(today)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: "successful prompts today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Lifetime")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(lifetime)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "Last prompt")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: lastEntryAt.map(relative) ?? "—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Resets at 00:00 local.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(verbatim: "Claude Code Stop hook writes to:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: logPath)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func relative(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
