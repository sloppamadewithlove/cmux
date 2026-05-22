import AppKit

/// Dedicated keybindings that type a CLI launch command into the currently
/// focused terminal pane and press Enter.
///
/// To change a chord or its command, edit `defaultBindings` below and push.
/// The chord check is O(bindings.count) per keypress and short-circuits before
/// any allocation, so it adds negligible overhead.
@MainActor
final class CLILauncherShortcuts {
    static let shared = CLILauncherShortcuts()

    struct Binding {
        /// Normalized event character, lowercased.
        let key: String
        /// Device-independent modifier mask the event must equal exactly.
        let modifiers: NSEvent.ModifierFlags
        /// Shell command sent to the focused terminal followed by `\n`. The user
        /// is responsible for being at a shell prompt when triggering.
        let command: String
        /// Human-readable label (used only for logging).
        let label: String
    }

    /// Triple-modifier (Cmd+Ctrl+Opt) chords were chosen to avoid colliding with
    /// any existing Cmux or system shortcut. Edit freely.
    static let defaultBindings: [Binding] = [
        Binding(
            key: "c",
            modifiers: [.command, .control, .option],
            command: "claude --dangerously-skip-permissions",
            label: "claude"
        ),
        Binding(
            key: "x",
            modifiers: [.command, .control, .option],
            command: "codex --dangerously-bypass-approvals-and-sandbox",
            label: "codex"
        ),
        Binding(
            key: "g",
            modifiers: [.command, .control, .option],
            command: "gemini --yolo",
            label: "gemini"
        ),
        Binding(
            key: "s",
            modifiers: [.command, .control, .option],
            command: "superGemma",
            label: "superGemma"
        ),
    ]

    var bindings: [Binding] = CLILauncherShortcuts.defaultBindings

    /// Closure that returns the panel currently receiving keyboard input, or nil
    /// if the focused workspace has no terminal pane. Wired from AppDelegate so
    /// this file does not depend on AppDelegate's internals.
    var focusedTerminalPanelProvider: (@MainActor () -> TerminalPanel?)?

    private var monitor: Any?

    func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event) ? nil : event
        }
    }

    func handleShortcutEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        // Cheap reject: every binding here uses Cmd+Ctrl+Opt. If none of those are
        // held, return immediately without touching `charactersIgnoringModifiers`.
        let triple: NSEvent.ModifierFlags = [.command, .control, .option]
        guard mods.contains(triple) else { return false }

        let chars = KeyboardLayout.normalizedCharacters(for: event).lowercased()
        guard !chars.isEmpty else { return false }

        for binding in bindings where mods == binding.modifiers && chars == binding.key {
            guard let panel = focusedTerminalPanelProvider?() else {
                NSSound.beep()
                return true
            }
            panel.sendText(binding.command + "\n")
            return true
        }
        return false
    }
}
