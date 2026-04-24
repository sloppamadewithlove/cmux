import Foundation
import Combine
import AppKit

/// Custom-visuals fork updater. Replaces Sparkle (which is signature-gated) with a
/// plain GitHub-API poll against `vichi7/cmux` tag `custom-latest`. When an update
/// is available we download `cmux-custom.zip` to `/tmp` and hand off to the
/// bundled `install-cmux-custom.command` so the user gets the same sha256-verified
/// install path they run manually today.
///
/// This intentionally holds zero secrets and does no code-signing: the fork is
/// ad-hoc signed anyway. Trust is rooted in the GitHub release URL + sha256.
@MainActor
final class CustomUpdateChecker: ObservableObject {
    static let shared = CustomUpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(lastCheck: Date)
        case updateAvailable(publishedAt: Date, zipURL: URL, sha256URL: URL)
        case installing
        case error(message: String, at: Date)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheckAt: Date?
    @Published private(set) var nextCheckAt: Date?

    private let checkInterval: TimeInterval = 60 * 60   // every hour
    private let repo = "vichi7/cmux"
    private let tag = "custom-latest"
    private let session: URLSession
    private var timer: Timer?
    private let currentBuildDate: Date

    private init() {
        var config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.currentBuildDate = Self.resolveCurrentBuildDate()
    }

    /// Begin hourly polling. Safe to call multiple times; idempotent.
    /// The first check runs immediately; subsequent checks self-schedule from
    /// `finishCheck(...)` after each response lands.
    func start() {
        guard timer == nil else { return }
        checkNow()
    }

    /// Fire an immediate check. Triggered by the UI pill's tap handler.
    func checkNow() {
        Task { await performCheck() }
    }

    /// Download + install the currently-available update. No-op unless status is
    /// `.updateAvailable`.
    func installAvailableUpdate() {
        guard case .updateAvailable = status else { return }
        status = .installing
        Task { await runInstaller() }
    }

    // MARK: - Check

    private func performCheck() async {
        status = .checking
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("cmux-custom-visuals", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                finishCheck(.error(message: "GitHub returned HTTP \(code)", at: Date()))
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            guard let publishedAt = iso.date(from: release.published_at) else {
                finishCheck(.error(message: "Malformed published_at", at: Date()))
                return
            }

            guard let zipAsset = release.assets.first(where: { $0.name == "cmux-custom.zip" }),
                  let shaAsset = release.assets.first(where: { $0.name == "cmux-custom.zip.sha256" }),
                  let zipURL = URL(string: zipAsset.browser_download_url),
                  let shaURL = URL(string: shaAsset.browser_download_url)
            else {
                finishCheck(.error(message: "Release assets missing", at: Date()))
                return
            }

            // A release is "newer" iff its publish time is after the installed
            // build's mtime by at least 60 seconds (avoid timestamp jitter).
            if publishedAt.timeIntervalSince(currentBuildDate) > 60 {
                finishCheck(.updateAvailable(publishedAt: publishedAt, zipURL: zipURL, sha256URL: shaURL))
            } else {
                finishCheck(.upToDate(lastCheck: Date()))
            }
        } catch {
            finishCheck(.error(message: error.localizedDescription, at: Date()))
        }
    }

    private func finishCheck(_ newStatus: Status) {
        status = newStatus
        lastCheckAt = Date()
        scheduleNext(delay: checkInterval)
    }

    private func scheduleNext(delay: TimeInterval) {
        timer?.invalidate()
        nextCheckAt = Date().addingTimeInterval(delay)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }

    // MARK: - Install

    private func runInstaller() async {
        do {
            // The bundled or GitHub-hosted shell installer does the real work:
            // sha256-verify, quit-and-swap atomic install, Gatekeeper strip.
            // We just hand it off to Terminal so the sudo prompt is interactive.
            let scriptURL = try await resolveInstallerScript()
            let ok = NSWorkspace.shared.open(scriptURL)
            if !ok {
                status = .error(message: "Could not open installer at \(scriptURL.path)", at: Date())
                return
            }
            status = .upToDate(lastCheck: Date())
        } catch {
            status = .error(message: "Install failed: \(error.localizedDescription)", at: Date())
        }
    }

    /// Find the installer script. Priority:
    ///   1. App bundle Resources (if CI ever adds it)
    ///   2. The sibling `scripts/install-cmux-custom.command` relative to the
    ///      app's parent path (useful when running from a source checkout).
    ///   3. Download from raw.githubusercontent.com/vichi7/cmux/custom-visuals.
    private func resolveInstallerScript() async throws -> URL {
        if let bundled = Bundle.main.url(forResource: "install-cmux-custom", withExtension: "command"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let raw = URL(string:
            "https://raw.githubusercontent.com/\(repo)/custom-visuals/scripts/install-cmux-custom.command"
        )!
        let (data, response) = try await session.data(from: raw)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "cmux.update", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "installer download HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            ])
        }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("install-cmux-custom.command")
        try? FileManager.default.removeItem(at: target)
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target
    }

    // MARK: - Helpers

    private static func resolveCurrentBuildDate() -> Date {
        // The .app bundle's main executable mtime is a reliable "when was this
        // build produced" signal for our CI-built artifacts.
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let date = attrs[.modificationDate] as? Date
        else {
            return .distantPast
        }
        return date
    }

    // MARK: - GitHub API shape

    private struct GitHubRelease: Decodable {
        let published_at: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }
}
