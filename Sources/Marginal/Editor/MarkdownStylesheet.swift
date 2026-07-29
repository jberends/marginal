import Foundation

/// The CSS behind every HTML rendering of a document — Preview mode on screen and PDF export.
/// One stylesheet, so the three renderings of a document (screen, PDF, Copy as HTML) can never
/// drift apart. Colour values mirror DesignPalette / the design system's token sheet.
enum MarkdownStylesheet {

    enum Appearance {
        case light
        case dark
    }

    private struct Tokens {
        let paper: String
        let ink: String
        let heading: String
        let panel: String
        let hairline: String
        let accent: String
        let muted: String

        static let light = Tokens(
            paper: "#FFFEFC", ink: "#2C2C2B", heading: "#232323", panel: "#F7F6F3",
            hairline: "#E6E5E3", accent: "#8E1FCB", muted: "#6B6A67"
        )

        static let dark = Tokens(
            paper: "#1E1E1D", ink: "#E8E7E3", heading: "#F2F1EE", panel: "#252524",
            hairline: "#33332F", accent: "#CB7DF7", muted: "#A6A49F"
        )
    }

    /// Preview mode. Follows the window's appearance and the editor's own font size, so ⌘+/⌘−
    /// keep working in Preview.
    static func screenCSS(appearance: Appearance, bodyPointSize: CGFloat) -> String {
        let tokens = appearance == .light ? Tokens.light : Tokens.dark
        return rules(
            tokens: tokens,
            bodySize: "\(Int(bodyPointSize.rounded()))px",
            extra: """
              body { background: \(tokens.paper); padding: 24px 40px 64px; }
              ::selection { background: \(appearance == .light ? "#EDD5F9" : "#472C63"); }
            """
        )
    }

    /// PDF export. Always the light tokens at 12pt — print goes on white paper regardless of
    /// the window's appearance — plus pagination rules the screen doesn't need.
    static var printCSS: String {
        rules(
            tokens: .light,
            bodySize: "12pt",
            extra: """
              body { margin: 0; }
              pre { page-break-inside: avoid; }
              h1, h2, h3 { page-break-after: avoid; }
            """
        )
    }

    private static func rules(tokens: Tokens, bodySize: String, extra: String) -> String {
        """
          body {
            font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            font-size: \(bodySize); line-height: 1.5; color: \(tokens.ink);
          }
          h1, h2, h3, h4, h5, h6 { color: \(tokens.heading); font-weight: 600; line-height: 1.25; }
          h1 { font-size: 1.875em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
          h4 { font-size: 1.125em; } h5 { font-size: 1em; } h6 { font-size: 0.875em; }
          blockquote {
            margin: 0; padding-left: 14px; border-left: 3px solid \(tokens.ink);
            color: \(tokens.muted);
          }
          code {
            font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 0.85em;
            color: \(tokens.accent); background: \(tokens.panel); border-radius: 4px; padding: 1px 4px;
          }
          pre {
            background: \(tokens.panel); border-radius: 10px; padding: 16px 22px; overflow-x: auto;
          }
          pre code { color: \(tokens.ink); background: none; padding: 0; }
          a { color: \(tokens.accent); }
          hr { border: 0; border-top: 1px solid \(tokens.hairline); }
          li { margin-bottom: 6px; }
        \(extra)
        """
    }

    /// Wraps rendered block HTML in a complete document.
    static func document(body: String, title: String, css: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        <style>
        \(css)
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
