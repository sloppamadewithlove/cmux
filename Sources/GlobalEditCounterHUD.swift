import SwiftUI

/// Top-right floating pill showing the lifetime "edits across any project" tally.
/// Hover to see the most recent interactions in a popover; the same data streams to
/// `~/Library/Logs/cmux/edits.log` for `tail -f` consumption.
struct GlobalEditCounterHUD: View {
    @ObservedObject private var counter = GlobalEditCounter.shared
    @State private var showingPopover: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 10, weight: .semibold))
            Text("\(counter.total)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(.primary.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
        .padding(.top, 4)
        .padding(.trailing, 8)
        .onHover { hovering in
            showingPopover = hovering
        }
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            RecentEditsList(entries: counter.recent, total: counter.total, logPath: counter.logFileURL.path)
        }
        .help(Text(verbatim: "Total edits across all projects: \(counter.total)\nTail live: tail -f \(counter.logFileURL.path)"))
    }
}

private struct RecentEditsList: View {
    let entries: [GlobalEditCounter.Entry]
    let total: Int
    let logPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: "Edits")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(verbatim: "\(total) total")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if entries.isEmpty {
                Text(verbatim: "No edits recorded yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: 8) {
                        Text(verbatim: relativeTime(entry.timestamp))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: entry.workspaceTitle.isEmpty ? "(workspace)" : entry.workspaceTitle)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(verbatim: entry.directory.isEmpty ? "(no cwd)" : entry.directory)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Live tail:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: "tail -f \(logPath)")
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
