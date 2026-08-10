import XCTest
import AppKit
@testable import Marginal

final class BlockViewFactoryTests: XCTestCase {
    func testHeadingAttributesMatchTokenScale() {
        let attrs = BlockViewFactory.attributes(for: .heading(level: 1, InlineText("x")),
                                                baseFont: .systemFont(ofSize: 16))
        let font = attrs[.font] as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 30, accuracy: 0.01)
    }

    @MainActor
    func testRenderRoundTripsInlineText() {
        let tv = BlockTextView()
        var t = InlineText("a ")
        t.append(InlineText(runs: [InlineRun(text: "b", style: .bold)]))
        tv.render(t, asKind: .paragraph(t), baseFont: .systemFont(ofSize: 16))
        XCTAssertEqual(tv.currentInlineText, t)
    }

    @MainActor
    func testRenderRoundTripsLinkOnlyRunWithoutSpuriousUnderline() {
        let tv = BlockTextView()
        let t = InlineText(runs: [InlineRun(text: "click", style: [], linkURL: "https://example.com")])
        tv.render(t, asKind: .paragraph(t), baseFont: .systemFont(ofSize: 16))
        let result = tv.currentInlineText
        XCTAssertEqual(result, t)
        XCTAssertEqual(result.runs.first?.style, [])
        XCTAssertEqual(result.runs.first?.linkURL, "https://example.com")
    }

    @MainActor
    func testRenderRoundTripsBoldCodeRun() {
        let tv = BlockTextView()
        let t = InlineText(runs: [InlineRun(text: "code", style: [.bold, .code])])
        tv.render(t, asKind: .paragraph(t), baseFont: .systemFont(ofSize: 16))
        XCTAssertEqual(tv.currentInlineText, t)
    }

    @MainActor
    func testRenderRoundTripsExplicitUnderlineOnLinkRun() {
        let tv = BlockTextView()
        let t = InlineText(runs: [InlineRun(text: "click", style: [.underline], linkURL: "https://example.com")])
        tv.render(t, asKind: .paragraph(t), baseFont: .systemFont(ofSize: 16))
        let result = tv.currentInlineText
        XCTAssertEqual(result, t)
        XCTAssertEqual(result.runs.first?.style, [.underline])
    }

    @MainActor
    func testFactoryProducesViewPerKind() {
        final class Sink: NSObject, BlockTextViewDelegate { /* empty conformance, all methods no-op */
            func blockTextView(_ v: BlockTextView, didEditInlineText t: InlineText) {}
            func blockTextViewDidPressEnter(_ v: BlockTextView, atOffset o: Int) {}
            func blockTextViewDidBackspaceAtStart(_ v: BlockTextView) {}
            func blockTextViewDidPressTab(_ v: BlockTextView, backward: Bool) {}
            func blockTextView(_ v: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat) {}
            func blockTextView(_ v: BlockTextView, selectionEscapedBoundary up: Bool) {}
            func blockTextView(_ v: BlockTextView, didToggleStyle t: InlineText, selection: NSRange) {}
        }
        let sink = Sink()
        for kind: BlockKind in [.paragraph(InlineText("p")), .divider,
                                .codeBlock(language: nil, "x"),
                                .listItem(style: .bullet, indent: 1, InlineText("i"))] {
            XCTAssertNotNil(BlockViewFactory.view(for: Block(kind: kind), baseFont: .systemFont(ofSize: 16),
                                                  textDelegate: sink), String(describing: kind))
        }
    }
}
