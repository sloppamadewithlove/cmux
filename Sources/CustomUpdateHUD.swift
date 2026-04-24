import SwiftUI

/// Top-trailing pill replacing Sparkle's update UI for the custom-visuals fork.
/// Shows:
///   • "Up to date — next check in 54m"           (passive countdown)
///   • "Checking…"                                (in-flight)
///   • "Update available — click to install"      (actionable)
///   • "Update failed: <msg>"                     (transient)
struct CustomUpdateHUD: View {
    @ObservedObject private var checker = CustomUpdateChecker.shared
    @State private var tick = Date()

    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.trailing, 8)
        .onReceive(tickTimer) { tick = $0 }
        .help(Text(verbatim: helpText))
    }

    private var icon: String {
        switch checker.status {
        case .idle, .upToDate:       return "checkmark.seal"
        case .checking:              return "arrow.triangle.2.circlepath"
        case .updateAvailable:       return "arrow.down.circle.fill"
        case .installing:            return "hourglass"
        case .error:                 return "exclamationmark.triangle.fill"
        }
    }

    private var label: String {
        switch checker.status {
        case .idle:
            return "Update: starting…"
        case .checking:
            return "Checking for update…"
        case .upToDate:
            return "Up to date · next \(countdownString)"
        case .updateAvailable:
            return "Update available — install"
        case .installing:
            return "Installing…"
        case .error(let msg, _):
            return "Update error — retry in \(countdownString) (\(brief(msg)))"
        }
    }

    private var foreground: Color {
        switch checker.status {
        case .updateAvailable: return .white
        case .error:           return .white
        default:               return .primary.opacity(0.9)
        }
    }

    private var background: AnyShapeStyle {
        switch checker.status {
        case .updateAvailable:
            return AnyShapeStyle(Color.accentColor.opacity(0.9))
        case .error:
            return AnyShapeStyle(Color.red.opacity(0.85))
        default:
            return AnyShapeStyle(Material.ultraThin)
        }
    }

    private var countdownString: String {
        let _ = tick                                 // re-render every second
        guard let target = checker.nextCheckAt else { return "—" }
        let seconds = max(0, Int(target.timeIntervalSince(Date())))
        let m = seconds / 60
        let s = seconds % 60
        if m >= 60 {
            let h = m / 60
            return "\(h)h\(m % 60)m"
        }
        if m > 0 { return "\(m)m\(String(format: "%02d", s))s" }
        return "\(s)s"
    }

    private var helpText: String {
        switch checker.status {
        case .updateAvailable(let publishedAt, _, _):
            return "New custom-latest release from \(publishedAt.formatted(date: .abbreviated, time: .shortened)). Click to install."
        case .upToDate(let last):
            return "Last checked \(last.formatted(date: .omitted, time: .shortened)). Auto-checks hourly."
        case .error(let msg, let at):
            return "Update check failed at \(at.formatted(date: .omitted, time: .shortened)): \(msg)"
        default:
            return "Cmux custom-visuals updater"
        }
    }

    private func brief(_ msg: String) -> String {
        let limit = 28
        return msg.count > limit ? String(msg.prefix(limit - 1)) + "…" : msg
    }

    private func onTap() {
        switch checker.status {
        case .updateAvailable:
            checker.installAvailableUpdate()
        default:
            checker.checkNow()
        }
    }
}
