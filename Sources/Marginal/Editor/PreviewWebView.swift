import AppKit
import WebKit

/// Preview mode's surface: a read-only WKWebView showing the document rendered through the same
/// MarkdownHTMLRenderer that drives PDF export and Copy as HTML. Because it renders real HTML, a
/// paragraph's soft newlines collapse into flowing text — which the AppKit text view can never do,
/// since its storage is the literal file.
///
/// Every emitted block carries a `data-line` attribute, so scroll position can be handed back and
/// forth with the editing surfaces.
@MainActor
final class PreviewWebView: NSView {

    private let webView: WKWebView

    /// The 1-based source line of each rendered block, in document order. Empty until `load`.
    private(set) var blockSourceLines: [Int] = []

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        // The rendered HTML comes from the user's own document, not a trusted app resource, so it
        // should not be able to run script. This class still drives scroll positioning itself via
        // evaluateJavaScript, which is host-evaluated script and unaffected by this page-content flag.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: frameRect, configuration: configuration)
        super.init(frame: frameRect)

        webView.translatesAutoresizingMaskIntoConstraints = false
        // The document's own paper colour comes from the stylesheet; keep the web view itself
        // from flashing white behind it on load. underPageBackgroundColor (public, macOS 12+) is
        // the documented replacement for the old `drawsBackground` private-API KVC hack.
        webView.underPageBackgroundColor = .clear
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(markdown: String, title: String, fontSize: CGFloat, appearance: MarkdownStylesheet.Appearance) {
        blockSourceLines = MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: markdown)
        webView.loadHTMLString(
            Self.documentHTML(markdown: markdown, title: title, fontSize: fontSize, appearance: appearance),
            baseURL: nil
        )
    }

    /// Scrolls the block containing `line` to the top of the view.
    func scrollToSourceLine(_ line: Int) {
        guard let anchor = MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: line, in: blockSourceLines) else { return }
        webView.evaluateJavaScript(Self.scrollScript(forSourceLine: anchor))
    }

    /// The source line of the topmost block currently visible, for handing position back to the
    /// editing surfaces. Completes with nil when nothing is rendered yet.
    func topmostVisibleSourceLine(completion: @escaping (Int?) -> Void) {
        webView.evaluateJavaScript(Self.topmostVisibleLineScript) { value, _ in
            completion((value as? NSNumber)?.intValue)
        }
    }

    static func documentHTML(
        markdown: String,
        title: String,
        fontSize: CGFloat,
        appearance: MarkdownStylesheet.Appearance
    ) -> String {
        MarkdownStylesheet.document(
            body: MarkdownHTMLRenderer.html(fromMarkdown: markdown),
            title: title,
            css: MarkdownStylesheet.screenCSS(appearance: appearance, bodyPointSize: fontSize)
        )
    }

    static func scrollScript(forSourceLine line: Int) -> String {
        """
        (function () {
          var el = document.querySelector('[data-line="\(line)"]');
          if (el) { el.scrollIntoView({ block: 'start' }); }
        })();
        """
    }

    /// Returns the `data-line` of the first block whose bottom edge is still below the top of the
    /// viewport — i.e. the block the reader is looking at.
    static let topmostVisibleLineScript = """
    (function () {
      var blocks = document.querySelectorAll('[data-line]');
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].getBoundingClientRect().bottom > 0) {
          return parseInt(blocks[i].getAttribute('data-line'), 10);
        }
      }
      return null;
    })();
    """
}
