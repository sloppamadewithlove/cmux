import SwiftUI

/// Floating pill at top-center of a workspace showing three pieces of context for
/// the currently focused terminal pane:
///   1. Exit status of the last completed foreground command (— when unknown).
///      Note: this is *not* a git branch indicator. Branch was removed per the
///      customization spec; to bring it back, observe
///      `workspace.panelGitBranches[panelId]` and add another HStack chunk.
///   2. Today's successful prompt count, scoped to the current project (the
///      closest enclosing `.git` ancestor of the focused panel's directory).
///      Tapping the count opens a popover with project / global breakdown.
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
    @ObservedObject private var counter = GlobalEditCounter.shared
    @State private var showingCounterPopover: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: exitIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(exitColor)
                Text(exitLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(exitColor)
            }

            Divider()
                .frame(height: 12)

            Button(action: { showingCounterPopover.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.yellow)
                    Text(verbatim: "\(counter.currentProjectToday)")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(counter.currentProjectToday)))
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingCounterPopover, arrowEdge: .top) {
                PromptCounterPopover(
                    projectName: counter.currentProjectName,
                    projectToday: counter.currentProjectToday,
                    projectLifetime: counter.currentProjectLifetime,
                    globalToday: counter.today,
                    globalLifetime: counter.lifetime,
                    lastEntryAt: counter.lastEntryAt,
                    logPath: counter.logFileURL.path
                )
            }
            .help(Text(verbatim: counterTooltip))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(radius: 8, y: 2)
        .padding(.top, -2)
        .frame(maxWidth: 640)
        .contentShape(Capsule())
        .onTapGesture { /* swallow */ }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(duration: 0.3), value: counter.currentProjectToday)
        .onAppear {
            counter.setCurrentProject(directory: panel.directory)
        }
        .onChange(of: panel.directory) { _, newValue in
            counter.setCurrentProject(directory: newValue)
        }
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

    private var counterTooltip: String {
        let project = counter.currentProjectName.isEmpty ? "this project" : counter.currentProjectName
        return "Today: \(counter.currentProjectToday) prompts in \(project) · Global today: \(counter.today)"
    }
}

private struct PromptCounterPopover: View {
    let projectName: String
    let projectToday: Int
    let projectLifetime: Int
    let globalToday: Int
    let globalLifetime: Int
    let lastEntryAt: Date?
    let logPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(projectToday)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "successful prompts today")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(verbatim: projectName.isEmpty ? "(no project context)" : "in \(projectName)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            HStack(spacing: 16) {
                stat(label: "Project lifetime", value: "\(projectLifetime)")
                Spacer()
                stat(label: "Global today", value: "\(globalToday)")
                Spacer()
                stat(label: "Global lifetime", value: "\(globalLifetime)")
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if let lastEntryAt {
                    Text(verbatim: "Last prompt: \(relative(lastEntryAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "Resets at 00:00 local. Project = closest .git ancestor.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(verbatim: "Claude Code Stop hook writes to:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Text(verbatim: logPath)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    @ViewBuilder
    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
    }

    private func relative(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
