import SwiftUI

/// Floating pill at top-center of a workspace showing two pieces of context for the
/// currently focused terminal pane:
///   1. Working directory (truncated to home-relative form when possible)
///   2. Exit status of the last completed foreground command (— when unknown)
///
/// Branch was removed per the customization spec. To bring it back, observe
/// `workspace.panelGitBranches[panelId]` and add a third HStack chunk.
struct ActiveTabHUD: View {
    @ObservedObject var workspace: Workspace

    var body: some View {
        Group {
            if let panel = workspace.focusedTerminalPanel {
                FocusedPanelPillBody(panel: panel)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workspace.focusedPanelId)
    }
}

/// Inner view holds an `@ObservedObject` on the panel itself so directory / exit-status
/// updates re-render the pill without invalidating the parent workspace view tree.
private struct FocusedPanelPillBody: View {
    @ObservedObject var panel: TerminalPanel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                Text(displayDirectory)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()
                .frame(height: 12)

            HStack(spacing: 4) {
                Image(systemName: exitIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(exitColor)
                Text(exitLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(exitColor)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(radius: 8, y: 2)
        // Lifted into the title-bar safe area so it sits *above* the terminal,
        // not partially overlapping the top of the surface like before.
        .padding(.top, -2)
        .frame(maxWidth: 520)
        // Capture taps on the pill itself so clicks here don't pass through to the
        // terminal layer underneath (which was spawning a new tab/pane on each click).
        .contentShape(Capsule())
        .onTapGesture { /* swallow */ }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var displayDirectory: String {
        let raw = panel.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "(no cwd)" }
        let home = NSHomeDirectory()
        if raw == home { return "~" }
        if raw.hasPrefix(home + "/") {
            return "~" + raw.dropFirst(home.count)
        }
        return raw
    }

    private var exitLabel: String {
        guard let status = panel.lastCommandExitStatus else { return "—" }
        return status == 0 ? "0" : String(status)
    }

    private var exitIcon: String {
        guard let status = panel.lastCommandExitStatus else { return "minus.circle" }
        return status == 0 ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var exitColor: Color {
        guard let status = panel.lastCommandExitStatus else { return .secondary }
        return status == 0 ? .green : .red
    }
}
