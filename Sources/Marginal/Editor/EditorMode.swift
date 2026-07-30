import Foundation

/// The editor's three rendering surfaces. `allCases` order is the order they appear in the
/// status-bar control and the View menu, and it defines the ⌘⌥1/2/3 key equivalents.
enum EditorMode: String, CaseIterable {
    /// Monospace source: every marker visible and tinted, uniform font size, nothing reflows.
    case code
    /// WYSIWYG with markdown syntax revealing itself at the cursor. The default.
    case live
    /// Read-only rendered HTML, where a paragraph's soft newlines collapse into flowing text.
    case preview

    /// The key `EditorMode` persists under. Mirrors the existing "editorFontPointSize" key.
    static let defaultsKey = "editorMode"

    var title: String {
        switch self {
        case .code: return "Code"
        case .live: return "Live"
        case .preview: return "Preview"
        }
    }

    /// SF Symbol shown in the status-bar segmented control.
    var symbolName: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .live: return "text.cursor"
        case .preview: return "eye"
        }
    }

    /// The digit in this mode's ⌘⌥-modified View menu shortcut.
    var menuKeyEquivalent: String {
        switch self {
        case .code: return "1"
        case .live: return "2"
        case .preview: return "3"
        }
    }

    /// The last mode the user chose, or `.live` on first launch and for any unrecognized
    /// stored value (e.g. a mode written by a newer version of the app).
    static func persisted(in defaults: UserDefaults) -> EditorMode {
        guard let raw = defaults.string(forKey: defaultsKey), let mode = EditorMode(rawValue: raw) else {
            return .live
        }
        return mode
    }

    func persist(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
