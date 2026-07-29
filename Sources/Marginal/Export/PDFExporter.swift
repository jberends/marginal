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
        MarkdownStylesheet.document(
            body: MarkdownHTMLRenderer.html(fromMarkdown: markdown),
            title: title,
            css: MarkdownStylesheet.printCSS
        )
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
