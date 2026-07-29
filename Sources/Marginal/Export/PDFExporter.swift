import AppKit
import WebKit

/// Exports a markdown document to a paginated PDF by rendering the same HTML
/// MarkdownHTMLRenderer produces for copy-as-HTML into an offscreen WKWebView and
/// running a save-to-file print operation over it. Styling mirrors the design-system
/// tokens (paper page, ink text, violet inline code, semibold-max headings).
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    static let shared = PDFExporter()

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var destination: URL?
    private var completion: ((Error?) -> Void)?

    /// A4 in PostScript points.
    private static let paperSize = NSSize(width: 595, height: 842)

    func export(markdown: String, title: String, to url: URL, completion: @escaping (Error?) -> Void) {
        // One export at a time; a second request while busy just fails fast.
        guard self.completion == nil else {
            completion(CocoaError(.userCancelled))
            return
        }
        self.destination = url
        self.completion = completion

        let pageWidth = Self.paperSize.width
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: Self.paperSize.height))
        webView.navigationDelegate = self

        // The print operation requires the view to live in a window; this one is never shown.
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: pageWidth, height: Self.paperSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        self.webView = webView
        self.hostWindow = window

        webView.loadHTMLString(Self.pageHTML(markdown: markdown, title: title), baseURL: nil)
    }

    /// Wraps the rendered markdown body in a printable page styled on the design tokens.
    static func pageHTML(markdown: String, title: String) -> String {
        let body = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            font-size: 12pt; line-height: 1.5; color: #2C2C2B; margin: 0;
          }
          h1, h2, h3, h4, h5, h6 { color: #232323; font-weight: 600; line-height: 1.25; }
          h1 { font-size: 1.875em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
          blockquote {
            margin: 0; padding-left: 14px; border-left: 3px solid #2C2C2B;
          }
          code {
            font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 0.85em;
            color: #8E1FCB; background: #F7F6F3; border-radius: 4px; padding: 1px 4px;
          }
          pre {
            background: #F7F6F3; border-radius: 10px; padding: 16px 22px;
            overflow-x: auto; page-break-inside: avoid;
          }
          pre code { color: #2C2C2B; background: none; padding: 0; }
          a { color: #8E1FCB; }
          hr { border: 0; border-top: 1px solid #E6E5E3; }
          li { margin-bottom: 6px; }
          h1, h2, h3 { page-break-after: avoid; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = destination, let window = hostWindow else { return finish(CocoaError(.fileWriteUnknown)) }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = Self.paperSize
        printInfo.topMargin = 57      // ~2 cm
        printInfo.bottomMargin = 57
        printInfo.leftMargin = 57
        printInfo.rightMargin = 57
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // Known WKWebView print quirk: the operation's view needs an explicit frame.
        operation.view?.frame = NSRect(origin: .zero, size: Self.paperSize)
        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    // NSPrintOperation invokes the didRun selector on a background thread (observed:
    // __NSThread__start__ under _continueModalOperationToTheEnd) -- this must be
    // nonisolated, with an explicit hop back to the main actor.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            self.finish(success ? nil : CocoaError(.fileWriteUnknown))
        }
    }

    private func finish(_ error: Error?) {
        let callback = completion
        completion = nil
        destination = nil
        hostWindow?.contentView = nil
        hostWindow = nil
        webView = nil
        callback?(error)
    }
}
