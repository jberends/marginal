import AppKit

/// The editor's typeface. Avenir Next is what gives Bear its "luxury" reading feel -- a humanist
/// sans with generous, open letterforms that reads far warmer at long-form lengths than the
/// system UI font, which is tuned for interface chrome rather than prose. It ships with macOS,
/// so there is nothing to bundle, and every call falls back to the system font if it is ever
/// missing.
enum EditorFont {
    static func body(_ size: CGFloat) -> NSFont {
        NSFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    /// Headings and inline bold. Avenir Next's Demi Bold is the weight that corresponds to the
    /// design system's semibold (600) -- its Bold is heavier than the intended tone.
    static func semibold(_ size: CGFloat) -> NSFont {
        NSFont(name: "AvenirNext-DemiBold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    /// Table header cells: a touch heavier than body without reading as bold.
    static func medium(_ size: CGFloat) -> NSFont {
        NSFont(name: "AvenirNext-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
}
