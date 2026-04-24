import Foundation
import Combine
import os

/// Process-wide running tally of "edit interactions" across every project. An interaction
/// is any moment the user actively brings a terminal pane into focus — proxy for "I just
/// did something in this terminal." Persists across launches via UserDefaults and
/// streams every event to a log file you can `tail -f`.
///
/// The activity model is deliberately coarse: we count discrete focus events rather than
/// keystrokes, because (a) hooking the per-keystroke path is forbidden by cmux's
/// typing-latency policy, and (b) every meaningful "edit" in a CLI workflow begins with
/// the user focusing the relevant pane.
@MainActor
final class GlobalEditCounter: ObservableObject {
    static let shared = GlobalEditCounter()

    private static let totalDefaultsKey = "cmux.globalEditCounter.total"
    private static let recentFilenameLimit = 12

    @Published private(set) var total: Int
    @Published private(set) var recent: [Entry] = []

    /// Absolute path of the append-only log file. Surfaced so the user can
    /// `tail -f $(cat)` or open it from the Finder.
    let logFileURL: URL

    private let fileQueue = DispatchQueue(label: "com.cmux.globalEditCounter.log")
    private let isoFormatter: ISO8601DateFormatter

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let workspaceTitle: String
        let directory: String
    }

    private init() {
        self.total = UserDefaults.standard.integer(forKey: Self.totalDefaultsKey)
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/cmux", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("edits.log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    /// Record one interaction. Cheap on the main thread (one increment + one Combine
    /// notification); the disk write hops to a serial background queue.
    func recordInteraction(workspaceTitle: String, directory: String) {
        total &+= 1
        UserDefaults.standard.set(total, forKey: Self.totalDefaultsKey)

        let entry = Entry(
            timestamp: Date(),
            workspaceTitle: workspaceTitle,
            directory: directory
        )
        var nextRecent = recent
        nextRecent.insert(entry, at: 0)
        if nextRecent.count > Self.recentFilenameLimit {
            nextRecent = Array(nextRecent.prefix(Self.recentFilenameLimit))
        }
        recent = nextRecent

        let line = "\(isoFormatter.string(from: entry.timestamp))\ttotal=\(total)\tworkspace=\(workspaceTitle)\tcwd=\(directory)\n"
        let url = logFileURL
        fileQueue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// Manual reset (e.g. for a Settings "Reset counter" button). Doesn't truncate the log.
    func resetTotal() {
        total = 0
        UserDefaults.standard.set(0, forKey: Self.totalDefaultsKey)
        recent = []
    }
}
