import AppKit
import ObjectiveC.runtime
import SwiftUI

/// Public entry point for the draggable workspace metrics pill.
///
/// Earlier revisions of the timer were a SwiftUI `.overlay` mounted inside
/// `WorkspaceContentView`. That works visually for the top-center pill because
/// the title-bar strip has no AppKit portal, but the timer's draggable position
/// often lands inside the bonsplit pane area where the portaled Ghostty surface
/// (an NSWindow-hosted child view, not a SwiftUI sibling) renders above any
/// SwiftUI overlay below it. The result was a timer that was technically
/// rendered but stuck behind the terminal — invisible and undraggable.
///
/// Solution: host the pill in a borderless floating `NSPanel` that is added as
/// a child window of the cmux main window. As an `NSWindow` it sits at its own
/// window level (`.floating`), above every in-window content view including
/// the AppKit portal. Drag is handled by `isMovableByWindowBackground`, so the
/// user grabs the pill and AppKit moves the panel — true free-drag anywhere on
/// screen, not just within the cmux window. Position persists across launches
/// via `frameAutosaveName`.
///
/// Mounting contract:
/// - The `FloatingTimerOverlay` SwiftUI view itself is 0×0 and invisible. Its
///   only job is to wire a thin `NSView` into the host window so we can find
///   that window from AppKit and attach the panel to it.
/// - The caller (currently `WorkspaceContentView`) is responsible for mounting
///   this overlay only when the workspace is the active one
///   (`isWorkspaceInputActive`). cmux keeps inactive workspace views alive in
///   the tree, so without that gate every workspace's overlay would race to
///   own the same per-window panel.
struct FloatingTimerOverlay: View {
    let workspaceId: UUID

    var body: some View {
        FloatingTimerPanelHost(workspaceId: workspaceId)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

// MARK: - SwiftUI ↔ AppKit bridge

private struct FloatingTimerPanelHost: NSViewRepresentable {
    let workspaceId: UUID

    func makeNSView(context: Context) -> FloatingTimerHookView {
        FloatingTimerHookView(workspaceId: workspaceId)
    }

    func updateNSView(_ nsView: FloatingTimerHookView, context: Context) {
        nsView.update(workspaceId: workspaceId)
    }

    static func dismantleNSView(_ nsView: FloatingTimerHookView, coordinator: ()) {
        nsView.willGoAway()
    }
}

/// Invisible NSView whose sole purpose is to find its host `NSWindow` so the
/// matching `FloatingTimerPanel` can be parented to it. Using `viewDidMoveToWindow`
/// makes us robust to delayed window assignment (the SwiftUI hosting controller
/// may be configured before the window is keyed up).
private final class FloatingTimerHookView: NSView {
    private var workspaceId: UUID
    private weak var attachedWindow: NSWindow?

    init(workspaceId: UUID) {
        self.workspaceId = workspaceId
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            attachedWindow = window
            FloatingTimerPanelController.controller(for: window).show(workspaceId: workspaceId)
        } else if let prior = attachedWindow {
            // Pass our workspaceId so the controller only hides if WE are the
            // currently shown workspace. This protects against the workspace-
            // switch race where the new workspace's show() fires before the old
            // workspace's view-removal callback — without the guard, the new
            // workspace's panel would be hidden right after appearing.
            FloatingTimerPanelController.controller(for: prior)
                .hideIfMatching(workspaceId: workspaceId)
            attachedWindow = nil
        }
    }

    func update(workspaceId newId: UUID) {
        workspaceId = newId
        if let window = attachedWindow ?? window {
            FloatingTimerPanelController.controller(for: window).show(workspaceId: newId)
        }
    }

    func willGoAway() {
        if let prior = attachedWindow {
            FloatingTimerPanelController.controller(for: prior)
                .hideIfMatching(workspaceId: workspaceId)
            attachedWindow = nil
        }
    }
}

// MARK: - Per-window panel controller

/// One controller (and one panel) per cmux `NSWindow`. Stored on the window via
/// an objc associated object so multiple workspaces in the same window share a
/// single panel and a single autosaved drag position.
@MainActor
private final class FloatingTimerPanelController {
    private static var associationKey: UInt8 = 0

    static func controller(for window: NSWindow) -> FloatingTimerPanelController {
        if let existing = objc_getAssociatedObject(window, &associationKey) as? FloatingTimerPanelController {
            return existing
        }
        let made = FloatingTimerPanelController(parent: window)
        objc_setAssociatedObject(window, &associationKey, made, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return made
    }

    private weak var parent: NSWindow?
    private var panel: FloatingTimerPanel?
    private var currentWorkspaceId: UUID?

    private init(parent: NSWindow) {
        self.parent = parent
    }

    func show(workspaceId: UUID) {
        currentWorkspaceId = workspaceId
        let panel = ensurePanel()
        panel.update(workspaceId: workspaceId)
        attachToParentIfNeeded(panel)
        if !panel.isVisible {
            positionAtSensibleDefaultIfUnsetFrame(panel)
        }
        panel.orderFront(nil)
    }

    /// Hide the panel only if the workspace asking us to hide is still the one
    /// we're currently showing. Guards the workspace-switch race where the new
    /// workspace's show() can fire before the previous workspace's
    /// view-removal callback.
    func hideIfMatching(workspaceId: UUID) {
        guard currentWorkspaceId == workspaceId else { return }
        panel?.orderOut(nil)
        currentWorkspaceId = nil
    }

    private func ensurePanel() -> FloatingTimerPanel {
        if let existing = panel { return existing }
        let made = FloatingTimerPanel()
        panel = made
        return made
    }

    private func attachToParentIfNeeded(_ panel: FloatingTimerPanel) {
        guard let parent else { return }
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
        panel.order(.above, relativeTo: parent.windowNumber)
    }

    /// On first show, place the panel near the top-center of the parent window so
    /// it lands somewhere obvious. Subsequent launches restore the user's
    /// dragged position from frameAutosaveName.
    private func positionAtSensibleDefaultIfUnsetFrame(_ panel: FloatingTimerPanel) {
        guard let parent else { return }
        // If autosaved frame already moved us into a non-default position, don't
        // override it. Heuristic: the autosaved frame, if any, has been applied
        // by `setFrameAutosaveName` during init. We just nudge to the parent
        // window's top-center when the panel hasn't yet been ordered front.
        let parentFrame = parent.frame
        let inset: CGFloat = 16
        let topCenter = NSPoint(
            x: parentFrame.midX - (panel.frame.width / 2),
            y: parentFrame.maxY - inset
        )
        // Only set frame if it's still at AppKit's "no autosaved frame" default
        // (the frame we initialized with). Comparing against the init frame keeps
        // us from clobbering a restored position on app relaunch.
        if panel.frame.origin == FloatingTimerPanel.initialOrigin {
            panel.setFrameTopLeftPoint(topCenter)
        }
    }
}

// MARK: - The panel itself

/// Borderless floating NSPanel that hosts the timer pill. Always above the host
/// window's content because (a) it's a child window with `.above` ordering and
/// (b) it sits at `level = .floating`. Drag handled by AppKit via
/// `isMovableByWindowBackground`.
private final class FloatingTimerPanel: NSPanel {
    static let initialOrigin = NSPoint(x: 100, y: 100)
    private static let panelSize = CGSize(width: 296, height: 46)
    private let host: NSHostingView<FloatingTimerPill>
    private var workspaceId: UUID

    init() {
        // Build the SwiftUI hosting view with a placeholder UUID first; the
        // controller will call `update(workspaceId:)` immediately after init,
        // before the panel is ever ordered front. We assign all of our own
        // stored properties before calling super.init() to satisfy Swift's
        // Phase-1 init rules.
        let initialId = UUID()
        let pill = FloatingTimerPill(workspaceId: initialId)
        let hostView = NSHostingView(rootView: pill)
        hostView.autoresizingMask = [.width, .height]
        self.host = hostView
        self.workspaceId = initialId

        super.init(
            contentRect: NSRect(
                origin: Self.initialOrigin,
                size: Self.panelSize
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        contentView = hostView
        hostView.frame = NSRect(origin: .zero, size: Self.panelSize)
        // Versioned autosave name so this redesign starts with the new
        // top-center default instead of reusing the old timer-only position. The
        // `frameAutosaveName` property is read-only in Swift; the only way to
        // set it is via `setFrameAutosaveName(_:)`, which both registers the
        // name *and* immediately restores a previously-saved frame for that
        // name. On first launch the saved frame doesn't exist yet, the call
        // returns false, and FloatingTimerPanelController nudges the panel
        // near the parent window's top-center so it lands somewhere visible.
        _ = self.setFrameAutosaveName("cmux.floatingMetricsPanel.v1")
    }

    func update(workspaceId newId: UUID) {
        guard newId != workspaceId else { return }
        workspaceId = newId
        host.rootView = FloatingTimerPill(workspaceId: newId)
    }

    // Keep the panel from stealing focus from the cmux window. The user should
    // be able to type in the terminal while the pill floats above it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Pill content

/// Visual pill rendered inside the floating panel: idle timer, today's prompt
/// edits, and all-time prompt edits. No project/folder context is shown here.
private struct FloatingTimerPill: View {
    let workspaceId: UUID
    @ObservedObject private var store = PanelActivityStore.shared
    @ObservedObject private var counter = GlobalEditCounter.shared

    var body: some View {
        let _ = store.tick
        let remaining = store.remainingTime(workspaceId: workspaceId)
        let isExpired = remaining <= 0

        HStack(spacing: 10) {
            metric(label: "Timer", value: formatted(remaining), isExpired: isExpired)

            Divider()
                .frame(height: 16)

            metric(label: "Day", value: "\(counter.today)")

            Divider()
                .frame(height: 16)

            metric(label: "Ever", value: "\(counter.lifetime)")
        }
        .foregroundStyle(isExpired ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isExpired ? AnyShapeStyle(Color.red) : AnyShapeStyle(.ultraThinMaterial))
        )
        .overlay(
            Capsule().stroke(
                Color.white.opacity(0.18),
                lineWidth: 0.5
            )
        )
        .shadow(radius: 6, y: 2)
        // Outer breathing room so the shadow isn't clipped by panel bounds.
        .padding(6)
        .help(Text(verbatim: "Drag to reposition. Timer resets when a prompt completes. Day and Ever count prompt edits."))
        .accessibilityLabel(Text(verbatim: "Workspace metrics"))
        .accessibilityValue(Text(verbatim: "\(formatted(remaining)), \(counter.today) today, \(counter.lifetime) ever"))
        .animation(.spring(duration: 0.3), value: counter.today)
        .animation(.spring(duration: 0.3), value: counter.lifetime)
    }

    @ViewBuilder
    private func metric(label: String, value: String, isExpired: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isExpired ? Color.white.opacity(0.75) : Color.secondary)
            Text(verbatim: value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isExpired ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
