import Foundation

/// The surfaces `EditorModeController` drives. `DocumentViewController` is the only real
/// conformer; the protocol exists so mode dispatch can be tested without a window.
@MainActor
protocol EditorModeHost: AnyObject {
    /// Render the document as tinted monospace source.
    func renderCode()
    /// Render the document as WYSIWYG with reveal-at-cursor.
    func renderLive()
    /// Render the document as read-only HTML.
    func renderPreview()
    /// Show/hide the surfaces and chrome (gutter, status bar contents) this mode needs.
    /// Always called before the matching render.
    func applyChrome(for mode: EditorMode)
}

/// Owns which of the three editor modes is active, and is the single place that decides which
/// render path runs.
///
/// Before this existed, `DocumentViewController` repeated the branch
/// `isShowingSource ? applyPlainSourceRendering() : restyle(…)` at four separate call sites —
/// the mode toggle, text changes, selection changes and font-size changes. A three-way version
/// of that, duplicated four times, is how a feature like this rots. Callers now say `render()`
/// and this class decides what that means.
@MainActor
final class EditorModeController {

    private(set) var mode: EditorMode

    /// Weak because the host (`DocumentViewController`) owns this controller; a strong back
    /// reference would be a retain cycle. Every method below no-ops if `host` is nil rather than
    /// asserting. That's deliberately not a defense against a real runtime state: this controller
    /// is only ever reached through its host (there is no async hop or stored callback that could
    /// run after the host is gone), so in practice `host` cannot go nil while any of these methods
    /// are being invoked — when the host deallocates, this controller deallocates with it, and
    /// nothing calls in afterward. The guards exist to fail safe rather than crash if that
    /// invariant is ever violated (e.g. a test holds the controller past its host's lifetime),
    /// not to paper over an expected condition.
    private weak var host: EditorModeHost?
    private let defaults: UserDefaults

    init(host: EditorModeHost, defaults: UserDefaults = .standard) {
        self.host = host
        self.defaults = defaults
        self.mode = EditorMode.persisted(in: defaults)
    }

    /// Applies the starting mode's chrome and renders it. Separate from `init` so a host can
    /// finish building its views before anything draws.
    func activate() {
        applyAndRender()
    }

    /// Switches mode: persists the choice, swaps the chrome, renders the new surface.
    /// Selecting the mode that's already active does nothing — re-rendering Preview or
    /// restyling the whole document for a no-op change would be visible work for no reason.
    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        newMode.persist(in: defaults)
        applyAndRender()
    }

    /// Re-renders the active surface. The one call site for text changes, selection changes and
    /// font-size changes.
    func render() {
        guard let host else { return }
        switch mode {
        case .code: host.renderCode()
        case .live: host.renderLive()
        case .preview: host.renderPreview()
        }
    }

    private func applyAndRender() {
        host?.applyChrome(for: mode)
        render()
    }
}
