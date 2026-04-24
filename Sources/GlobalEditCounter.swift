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
/// The old focus-driven `recordInteraction(...)` API is preserved as a no-op so
/// the existing call site in `Workspace.focusPanel` keeps compiling; the focus
/// signal is not what the user wants to see any more.
@MainActor
final class GlobalEditCounter: ObservableObject {
    static let shared = GlobalEditCounter()

    @Published private(set) var today: Int = 0
    @Published private(set) var lifetime: Int = 0
    @Published private(set) var lastEntryAt: Date?

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
    func recordSyntheticPrompt(workspaceTitle: String = "") {
        let line = "{\"ts\":\"\(iso.string(from: Date()))\",\"source\":\"manual\",\"workspace\":\"\(workspaceTitle)\"}\n"
        append(line)
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
        let (today, lifetime, last) = Self.countEntries(in: logFileURL)
        self.today = today
        self.lifetime = lifetime
        self.lastEntryAt = last
    }

    /// Linear scan of the log. File is tiny (one line per prompt ≈ 80 bytes;
    /// 1000 prompts/day ≈ 80KB), so O(n) per update is fine. If someone hammers
    /// this past 100k lines we can switch to a tail-watcher, but not before.
    private static func countEntries(in url: URL) -> (today: Int, lifetime: Int, last: Date?) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return (0, 0, nil)
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]

        var today = 0
        var lifetime = 0
        var last: Date?

        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            guard let ts = extractTimestamp(from: String(line)) else { continue }
            let date = iso.date(from: ts) ?? isoFallback.date(from: ts)
            guard let date else { continue }
            lifetime += 1
            if date >= todayStart { today += 1 }
            if last == nil || date > last! { last = date }
        }
        return (today, lifetime, last)
    }

    /// Accepts either:
    ///   • a raw ISO-8601 timestamp as the whole line (`2026-04-24T18:22:11Z`)
    ///   • a JSON object with a top-level `"ts"` field
    /// This keeps the hook command surface as small as possible without locking
    /// future hooks into a rigid schema.
    private static func extractTimestamp(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first == "{" {
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ts = obj["ts"] as? String {
                return ts
            }
            return nil
        }
        return trimmed
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
            // If the file was renamed/deleted, re-open and re-observe.
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
