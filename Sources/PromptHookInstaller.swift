import Foundation
import os

/// Idempotently registers a Claude Code `Stop` hook that appends one JSON line
/// per completed prompt → response round trip to `~/.cmux/prompts.jsonl`.
///
/// The hook is the _only_ thing that feeds `GlobalEditCounter`'s "successful
/// prompts today" number — without it the counter sits at 0 forever. We install
/// it on every app launch (not just first) so that if the user wipes their
/// `~/.claude/settings.json`, the next Cmux launch restores the hook.
///
/// Safety properties:
///   • Never removes or reorders existing hooks.
///   • Detects its own marker (`cmux.promptCounter = true`) and skips re-adding.
///   • Writes the settings file atomically via a `.tmp` sibling + rename.
///   • Keeps a one-off `.cmux-backup-<ISO>` next to the original the first time
///     we touch it.
enum PromptHookInstaller {
    /// Distinctive substring baked into our hook's command line. Matching on this
    /// keeps our detection tolerant to Claude Code schema changes (no custom
    /// top-level keys on the hook entry) and to command tweaks that still point
    /// at the same log file.
    private static let commandSignature = ".cmux/prompts.jsonl"
    private static let logger = Logger(subsystem: "com.cmuxterm.app", category: "PromptHookInstaller")

    /// Ensure the Stop hook is present in `~/.claude/settings.json`. Returns
    /// `true` if the file was mutated this call, `false` if already up to date.
    @discardableResult
    static func installIfNeeded() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)

        ensureCounterDir(home: home)

        var settings = loadSettings(at: settingsURL) ?? [:]

        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        var stopHooks = (hooks["Stop"] as? [[String: Any]]) ?? []

        if stopHooks.contains(where: isOurHook) {
            return false
        }

        stopHooks.append(newHookEntry())
        hooks["Stop"] = stopHooks
        settings["hooks"] = hooks

        do {
            try backupIfFirstTime(settingsURL: settingsURL)
            try writeAtomically(settings: settings, to: settingsURL)
            logger.info("Installed Claude Code Stop hook for cmux prompt counter")
            return true
        } catch {
            logger.error("Failed to install prompt counter hook: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Hook shape

    private static func newHookEntry() -> [String: Any] {
        // Each new prompt-complete event appends a JSON line with a timestamp.
        // The counter tolerates either raw ISO or {"ts": "..."} so future hook
        // schema changes don't require a migration.
        let command =
            #"mkdir -p "$HOME/.cmux" && printf '{"ts":"%s","source":"claude-stop"}\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" >> "$HOME/.cmux/prompts.jsonl""#
        return [
            "matcher": "*",
            "hooks": [[
                "type": "command",
                "command": command,
            ]],
        ]
    }

    private static func isOurHook(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(commandSignature) == true }
    }

    // MARK: - File I/O

    private static func loadSettings(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func writeAtomically(settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let tmp = url.appendingPathExtension("tmp-cmux-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        // Replace the original in one syscall.
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    private static func backupIfFirstTime(settingsURL: URL) throws {
        let marker = settingsURL.deletingLastPathComponent()
            .appendingPathComponent(".cmux-settings-backup.done", isDirectory: false)
        if FileManager.default.fileExists(atPath: marker.path) { return }
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let stamp = iso.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = settingsURL.appendingPathExtension("cmux-backup-\(stamp)")
        try FileManager.default.copyItem(at: settingsURL, to: backup)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    private static func ensureCounterDir(home: URL) {
        let dir = home.appendingPathComponent(".cmux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
