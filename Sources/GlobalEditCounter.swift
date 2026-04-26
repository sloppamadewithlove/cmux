import Foundation
import Combine
import AppKit

/// Cross-project "successful prompts today" counter, shared with Claude Code via
/// a single append-only log at `~/.cmux/prompts.jsonl`. Each line is written by a
/// Claude Code `Stop` hook (see `PromptHookInstaller`) at the moment the
/// assistant finishes a response — i.e. one complete prompt → answer round trip.
/// The counter is the count of lines whose timestamp falls in the current local
/// day (midnight-to-midnight), so it "resets" automatically at 00:00 without a
/// background job touching the file.
///
/// In addition to the global counter, each entry also carries the `$PWD` of the
/// Claude Code session that produced it. The counter resolves that directory to
/// the closest enclosing git root and exposes per-project aggregates so the HUD
/// can show "today's prompts in this project" rather than the global total.
///
/// The old focus-driven `recordInteraction(...)` API is preserved as a no-op so
/// the existing call site in `Workspace.focusPanel` keeps compiling; the focus
/// signal is not what the user wants to see any more.
@MainActor
final class GlobalEditCounter: ObservableObject {
    static let shared = GlobalEditCounter()

    /// Global aggregates across all projects.
    @Published private(set) var today: Int = 0
    @Published private(set) var lifetime: Int = 0
    @Published private(set) var lastEntryAt: Date?

    /// Resolved project root (git toplevel, or the raw directory if none) for
    /// the currently focused panel. Drives the per-project aggregates below.
    @Published private(set) var currentProjectKey: String?
    /// Display name for the current project (the basename of `currentProjectKey`).
    @Published private(set) var currentProjectName: String = ""
    /// Today's prompt count restricted to the current project.
    @Published private(set) var currentProjectToday: Int = 0
    /// Lifetime prompt count restricted to the current project.
    @Published private(set) var currentProjectLifetime: Int = 0
    /// Most recent prompt timestamp restricted to the current project.
    @Published private(set) var currentProjectLastEntryAt: Date?

    /// Directory that holds the shared counter state. Chosen so Claude Code hooks
    /// can `echo >> $HOME/.cmux/prompts.jsonl` without knowing the app's bundle ID.
    let stateDir: URL
    let logFileURL: URL

    private var fileObserver: DispatchSourceFileSystemObject?
    private var dayRolloverTimer: Timer?
    private let iso: ISO8601DateFormatter

    private init() {
        self.iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let home = FileManager.default.homeDirectoryForCurrentUser
        self.stateDir = home.appendingPathComponent(".cmux", isDirectory: true)
        self.logFileURL = stateDir.appendingPathComponent("prompts.jsonl", isDirectory: false)

        ensureStateFiles()
        recompute()
        installFileObserver()
        scheduleMidnightRefresh()
    }

    /// Legacy no-op kept so `Workspace.focusPanel` still compiles. Focus events
    /// are not "successful prompts" in the current product definition.
    func recordInteraction(workspaceTitle: String, directory: String) {
        _ = workspaceTitle
        _ = directory
    }

    /// Test hook + manual-reset fallback. Writes a single entry as if the hook fired.
    func recordSyntheticPrompt(workspaceTitle: String = "", cwd: String = "") {
        let line = "{\"ts\":\"\(iso.string(from: Date()))\",\"cwd\":\"\(cwd)\",\"source\":\"manual\",\"workspace\":\"\(workspaceTitle)\"}\n"
        append(line)
    }

    /// Tell the counter which directory the focused panel is showing. The
    /// counter resolves it to the closest enclosing git root, stores that as
    /// `currentProjectKey`, and recomputes per-project aggregates. Pass `nil` or
    /// an empty string to clear the project context (zeroes the per-project
    /// numbers).
    func setCurrentProject(directory: String?) {
        let resolvedKey: String?
        let displayName: String
        if let directory,
           !directory.trimmingCharacters(in: .whitespaces).isEmpty {
            let root = Self.resolveProjectRoot(for: directory)
            resolvedKey = root
            displayName = (root as NSString).lastPathComponent
        } else {
            resolvedKey = nil
            displayName = ""
        }

        if resolvedKey == currentProjectKey && displayName == currentProjectName {
            return
        }
        currentProjectKey = resolvedKey
        currentProjectName = displayName
        recompute()
    }

    // MARK: - Internals

    private func ensureStateFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
        recompute()
    }

    private func recompute() {
        let result = Self.countEntries(in: logFileURL, currentProjectKey: currentProjectKey)
        self.today = result.today
        self.lifetime = result.lifetime
        self.lastEntryAt = result.last
        self.currentProjectToday = result.projectToday
        self.currentProjectLifetime = result.projectLifetime
        self.currentProjectLastEntryAt = result.projectLast
    }

    /// Linear scan of the log. File is tiny (one line per prompt ≈ 100 bytes;
    /// 1000 prompts/day ≈ 100KB), so O(n) per update is fine. If someone hammers
    /// this past 100k lines we can switch to a tail-watcher, but not before.
    private static func countEntries(
        in url: URL,
        currentProjectKey: String?
    ) -> (
        today: Int,
        lifetime: Int,
        last: Date?,
        projectToday: Int,
        projectLifetime: Int,
        projectLast: Date?
    ) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return (0, 0, nil, 0, 0, nil)
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())

        var today = 0
        var lifetime = 0
        var last: Date?
        var projectToday = 0
        var projectLifetime = 0
        var projectLast: Date?

        let rootCache = ProjectRootCache()

        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            guard let entry = parseEntry(String(line)) else { continue }
            lifetime += 1
            if entry.date >= todayStart { today += 1 }
            if last == nil || entry.date > last! { last = entry.date }

            // Per-project filtering: resolve the entry's recorded $PWD to its
            // git toplevel (or the directory itself if no .git ancestor) and
            // compare against the focused panel's resolved project root.
            if let currentProjectKey,
               let entryCwd = entry.cwd,
               !entryCwd.isEmpty {
                let entryRoot = rootCache.root(for: entryCwd)
                if entryRoot == currentProjectKey {
                    projectLifetime += 1
                    if entry.date >= todayStart { projectToday += 1 }
                    if projectLast == nil || entry.date > projectLast! {
                        projectLast = entry.date
                    }
                }
            }
        }

        return (today, lifetime, last, projectToday, projectLifetime, projectLast)
    }

    /// One log entry parsed into its date and (optional) cwd.
    private struct ParsedEntry {
        let date: Date
        let cwd: String?
    }

    /// Accepts:
    ///   • a raw ISO-8601 timestamp as the whole line (`2026-04-25T18:22:11Z`)
    ///   • a JSON object with at least `"ts"` and optionally `"cwd"`
    /// Tolerates the historical macOS-`%N` bug (see `parseTimestamp`).
    private static func parseEntry(_ line: String) -> ParsedEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var ts: String?
        var cwd: String?

        if trimmed.first == "{" {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ts = obj["ts"] as? String
                cwd = obj["cwd"] as? String
            }
        } else {
            ts = trimmed
        }

        guard let ts, let date = parseTimestamp(ts) else { return nil }
        return ParsedEntry(date: date, cwd: cwd)
    }

    /// Tolerant ISO-8601 parser. Accepts strict ISO with/without fractional
    /// seconds, and recovers from the historical macOS-`%N` bug where the hook
    /// produced literal `2026-04-25T02:33:52.3NZ` lines (BSD `date` does not
    /// expand `%N`).
    private static func parseTimestamp(_ ts: String) -> Date? {
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = strict.date(from: ts) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: ts) { return date }

        if let range = ts.range(of: #"\.\d?NZ$"#, options: .regularExpression) {
            let cleaned = ts.replacingCharacters(in: range, with: "Z")
            return basic.date(from: cleaned)
        }
        return nil
    }

    /// Resolve a directory to its enclosing git toplevel by walking up looking
    /// for a `.git` entry (file or dir — `.git` can be a file in worktrees).
    /// Falls back to the input path if no ancestor has `.git`. Marked
    /// `nonisolated` so the per-recompute `ProjectRootCache` can call it from
    /// any actor context.
    nonisolated fileprivate static func resolveProjectRoot(for path: String) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        let fm = FileManager.default
        while !url.path.isEmpty && url.path != "/" {
            let gitPath = url.appendingPathComponent(".git").path
            if fm.fileExists(atPath: gitPath) {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return path
    }

    private func installFileObserver() {
        let fd = open(logFileURL.path, O_EVTONLY)
        guard fd != -1 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.recompute()
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                source.cancel()
                self.fileObserver = nil
                self.ensureStateFiles()
                self.installFileObserver()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.fileObserver = source
    }

    private func scheduleMidnightRefresh() {
        let nextMidnight = Self.nextMidnight(after: Date())
        let delay = max(30, nextMidnight.timeIntervalSinceNow)
        dayRolloverTimer?.invalidate()
        dayRolloverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recompute()
                self?.scheduleMidnightRefresh()
            }
        }
    }

    private static func nextMidnight(after date: Date) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        return cal.startOfDay(for: tomorrow)
    }
}

/// Per-call cache so a single recompute over thousands of log lines doesn't
/// re-walk the same directory tree for every entry.
private final class ProjectRootCache {
    private var cache: [String: String] = [:]

    func root(for path: String) -> String {
        if let cached = cache[path] { return cached }
        let resolved = GlobalEditCounter.resolveProjectRoot(for: path)
        cache[path] = resolved
        return resolved
    }
}
