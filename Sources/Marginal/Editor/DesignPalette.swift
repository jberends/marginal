import AppKit

/// Marginal's brand palette, mirroring the design-system tokens in
/// marketing/Marginal Design System/tokens/colors.css. Every color is dynamic:
/// it resolves against the current appearance, so light and dark documents both
/// sit on warm paper rather than pure white/black.
enum DesignPalette {

    /// Single accent — violet. Inline code, checked task boxes, links.
    static let accent = dynamic(light: "#8E1FCB", dark: "#CB7DF7")

    /// Foreground drawn on top of an accent fill (the checkbox checkmark).
    static let accentOn = dynamic(light: "#FFFEFC", dark: "#1E1E1D")

    /// The page behind the document: paper, not white.
    static let surfacePage = dynamic(light: "#FFFEFC", dark: "#1E1E1D")

    /// Panels: code cards, inline-code chips, table header rows.
    static let surfaceCode = dynamic(light: "#F7F6F3", dark: "#252524")

    /// Text selection.
    static let selection = dynamic(light: "#EDD5F9", dark: "#472C63")

    /// Hairline rules: table grids, horizontal rules.
    static let hairline = dynamic(light: "#E6E5E3", dark: "#33332F")

    /// Syntax highlighting inside code cards — warm set from the token sheet.
    static let synString = dynamic(light: "#2F9E68", dark: "#7FCFA0")
    static let synNumber = dynamic(light: "#C98A16", dark: "#E0AB4B")
    static let synComment = dynamic(light: "#9A9895", dark: "#7C7A75")

    private static func dynamic(light: String, dark: String) -> NSColor {
        let lightColor = color(hex: light)
        let darkColor = color(hex: dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    private static func color(hex: String) -> NSColor {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
