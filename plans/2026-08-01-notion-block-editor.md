# Notion Block Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hidden-marker single-textview renderer with a Notion-style block editor over a `BlockDocument` model, markdown as canonical storage, plus a synced raw-markdown Code mode.

**Architecture:** A pure-Swift model layer (`BlockDocument` + parser + serializer + edit engine, Tasks 1–8) that is fully unit-tested with no AppKit, then a view layer (Tasks 9–16) of per-block NSTextViews driven by that engine. Spec: `specs/2026-08-01-notion-block-editor-design.md` — its behavior-inventory table is the contract; every row has a test in this plan.

**Tech Stack:** Swift 6, AppKit (TextKit 1), XCTest, xcodegen. No third-party dependencies.

## Global Constraints

- macOS 14.0 deployment target, Swift 6 (`project.yml` already sets both).
- Regenerate the project after adding files: `xcodegen generate` (sources are globbed from `Sources/Marginal`, tests from `Tests/MarginalTests` — new files are picked up automatically, but regenerate anyway after creating directories).
- Test command (used in every task): `xcodebuild test -project Marginal.xcodeproj -scheme Marginal -destination 'platform=macOS' -only-testing:MarginalTests/<TestClass> 2>&1 | grep -E "Test Suite|error: -\[|\*\* TEST"`. Full suite before every commit. If a failure names a test that no longer exists in source, run `xcodebuild clean` first (known stale-bundle issue).
- Sizing/colors: ratios of `baseFont.pointSize` per `specs/notion-design-tokens.md`; colors via `DesignPalette` (exists on main). Heading scale 1.875/1.5/1.25/1.125/1.0/0.875 semibold; bold = `.semibold` weight is WRONG for inline bold — inline bold uses weight 600 via `NSFont.systemFont(ofSize:weight:.semibold)`; code 0.85× mono.
- Every NSTextView created anywhere: `isAutomaticDashSubstitutionEnabled = false`, `isAutomaticQuoteSubstitutionEnabled = false`, `isAutomaticTextReplacementEnabled = false`, `allowsUndo = false` (undo is document-level, Task 15).
- Existing types reused (do not redefine): `TableAlignment` (`MarkdownDocumentModel.swift`), `MarkdownParser.parseInlineStyles/parseLinks/parseEmojiShortcodes/parseCodeHighlightTokens`, `GemojiTable`, `DesignPalette`, `MarkdownHTMLRenderer`, `MarkdownStylesheet`.
- Commit after every task with the message given in the task. Do not touch `MarkdownStyler`/`MarkdownLayoutManager`/`CursorRevealController` until Task 16 (the old Live path keeps working while the new one grows beside it).

## File Structure

```
Sources/Marginal/Blocks/            # Phase 1: pure model layer, no AppKit imports except Foundation
  BlockModel.swift                  # InlineStyle, InlineRun, InlineText, ListStyle, BlockKind, Block, BlockDocument, Caret
  InlineMarkdown.swift              # markdown fragment <-> InlineText
  MarkdownBlockParser.swift         # markdown document -> BlockDocument
  MarkdownSerializer.swift          # BlockDocument -> canonical markdown + line map
  BlockEditEngine.swift             # split/merge/convert/indent/list rules (behavior rows 1-10)
  TableEditEngine.swift             # cell update, row append, tab/enter navigation (rows 12-13)
  InlineAutoformat.swift            # live **bold** etc. conversion (row 8)
Sources/Marginal/BlockEditor/       # Phase 2: AppKit views
  BlockTextView.swift               # per-block NSTextView + boundary event delegate
  BlockViewFactory.swift            # Block -> NSView, incl. list gutter, quote bar, divider, code card
  BlockTableView.swift              # per-cell grid
  BlockEditorViewController.swift   # stack, focus choreography, selection escalation
  BlockSelectionController.swift    # whole-block selection state (row 11)
Tests/MarginalTests/
  BlockModelTests.swift, InlineMarkdownTests.swift, MarkdownBlockParserTests.swift,
  MarkdownSerializerTests.swift, BlockEditEngineTests.swift, TableEditEngineTests.swift,
  InlineAutoformatTests.swift, BlockEditorSmokeTests.swift, BlockVisualHarnessTests.swift
```

---

## Phase 1 — the engine (no UI; ends at a reviewable checkpoint)

### Task 1: Block model types

**Files:**
- Create: `Sources/Marginal/Blocks/BlockModel.swift`
- Test: `Tests/MarginalTests/BlockModelTests.swift`

**Interfaces:**
- Produces (used by every later task):

```swift
struct InlineStyle: OptionSet, Equatable, Hashable {
    let rawValue: Int
    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let strikethrough = InlineStyle(rawValue: 1 << 2)
    static let underline = InlineStyle(rawValue: 1 << 3)
    static let code = InlineStyle(rawValue: 1 << 4)
}
struct InlineRun: Equatable { var text: String; var style: InlineStyle = []; var linkURL: String? = nil }
struct InlineText: Equatable {
    var runs: [InlineRun]
    init(_ plain: String = "")            // one unstyled run ([] when plain is empty)
    init(runs: [InlineRun])               // normalizes: drops empty runs, merges equal-styled neighbors
    var plainText: String
    var length: Int                        // characters (String.count of plainText)
    func split(at offset: Int) -> (InlineText, InlineText)
    mutating func append(_ other: InlineText)
}
enum ListStyle: Equatable { case bullet; case ordered; case task(done: Bool) }
enum BlockKind: Equatable {
    case paragraph(InlineText)
    case heading(level: Int, InlineText)
    case listItem(style: ListStyle, indent: Int, InlineText)
    case quote(InlineText)
    case codeBlock(language: String?, String)
    case table(alignments: [TableAlignment], header: [InlineText], rows: [[InlineText]])
    case divider
}
struct Block: Equatable, Identifiable { let id: UUID; var kind: BlockKind; init(kind: BlockKind) }
struct BlockDocument: Equatable {
    var blocks: [Block]
    func index(of id: UUID) -> Int?
    subscript(id: UUID) -> Block? { get }
}
struct Caret: Equatable { var blockID: UUID; var offset: Int }
extension BlockKind {
    var inlineText: InlineText?           // nil for codeBlock/table/divider
    func replacingInlineText(_ t: InlineText) -> BlockKind   // no-op for the nil cases
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Marginal

final class BlockModelTests: XCTestCase {
    func testSplitInMiddleOfStyledRuns() {
        let text = InlineText(runs: [InlineRun(text: "ab"), InlineRun(text: "cd", style: .bold)])
        let (left, right) = text.split(at: 3)
        XCTAssertEqual(left.runs, [InlineRun(text: "ab"), InlineRun(text: "c", style: .bold)])
        XCTAssertEqual(right.runs, [InlineRun(text: "d", style: .bold)])
    }
    func testSplitAtZeroAndAtEnd() {
        let text = InlineText("abc")
        XCTAssertEqual(text.split(at: 0).0, InlineText(""))
        XCTAssertEqual(text.split(at: 3).1, InlineText(""))
    }
    func testAppendMergesEqualStyledNeighbors() {
        var a = InlineText("ab")
        a.append(InlineText("cd"))
        XCTAssertEqual(a.runs, [InlineRun(text: "abcd")])
    }
    func testInitNormalizesEmptyRuns() {
        let t = InlineText(runs: [InlineRun(text: ""), InlineRun(text: "x")])
        XCTAssertEqual(t.runs, [InlineRun(text: "x")])
    }
    func testReplacingInlineTextIsNoOpForDivider() {
        XCTAssertEqual(BlockKind.divider.replacingInlineText(InlineText("x")), .divider)
        XCTAssertNil(BlockKind.divider.inlineText)
    }
    func testDocumentIndexAndSubscript() {
        let b = Block(kind: .paragraph(InlineText("hi")))
        let doc = BlockDocument(blocks: [b])
        XCTAssertEqual(doc.index(of: b.id), 0)
        XCTAssertEqual(doc[b.id], b)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail to compile** (`-only-testing:MarginalTests/BlockModelTests`; expected: build error, types undefined)
- [ ] **Step 3: Implement `BlockModel.swift` exactly per the interface block.** `split(at:)` walks runs accumulating counts; splits the straddling run by `String.Index`. `append` concatenates run arrays then re-normalizes.
- [ ] **Step 4: Run tests, verify PASS; run full suite**
- [ ] **Step 5: Commit** — `feat(blocks): block document model types`

### Task 2: InlineMarkdown — fragment ↔ InlineText

**Files:**
- Create: `Sources/Marginal/Blocks/InlineMarkdown.swift`
- Test: `Tests/MarginalTests/InlineMarkdownTests.swift`

**Interfaces:**
- Consumes: `MarkdownParser.parseInlineStyles(in:)`, `.parseLinks(in:)`, `.parseEmojiShortcodes(in:)`, `InlineText`.
- Produces: `enum InlineMarkdown { static func parse(_ fragment: String) -> InlineText; static func serialize(_ text: InlineText) -> String }`
- Canonical serialization: `**bold**`, `*italic*`, `~~strike~~`, `<u>underline</u>`, `` `code` ``, `[text](url)`. Emoji shortcodes normalize to the literal emoji character at parse time (normalize-freely decision); serializer emits the character as-is.

- [ ] **Step 1: Write the failing tests**

```swift
final class InlineMarkdownTests: XCTestCase {
    func testParseBoldItalicCodeLink() {
        let t = InlineMarkdown.parse("a **b** *i* `c` [l](https://x.y)")
        XCTAssertEqual(t.plainText, "a b i c l")
        XCTAssertEqual(t.runs.first(where: { $0.text == "b" })?.style, .bold)
        XCTAssertEqual(t.runs.first(where: { $0.text == "i" })?.style, .italic)
        XCTAssertEqual(t.runs.first(where: { $0.text == "c" })?.style, .code)
        XCTAssertEqual(t.runs.first(where: { $0.text == "l" })?.linkURL, "https://x.y")
    }
    func testEmojiShortcodeNormalizesToCharacter() {
        XCTAssertEqual(InlineMarkdown.parse("ok :white_check_mark:").plainText, "ok ✅")
    }
    func testSerializeCanonical() {
        var t = InlineText("a ")
        t.append(InlineText(runs: [InlineRun(text: "b", style: .bold)]))
        t.append(InlineText(runs: [InlineRun(text: " ", style: []), InlineRun(text: "l", linkURL: "https://x.y")]))
        XCTAssertEqual(InlineMarkdown.serialize(t), "a **b** [l](https://x.y)")
    }
    func testRoundTripIsIdentity() {
        let sources = ["plain", "**b** mid *i*", "`code` and ~~gone~~ and <u>u</u>", "[l](https://x.y) end"]
        for s in sources {
            XCTAssertEqual(InlineMarkdown.serialize(InlineMarkdown.parse(s)), s, s)
        }
    }
    func testBoldItalicCombinedParsesToBothFlags() {
        let t = InlineMarkdown.parse("***bi***")
        XCTAssertEqual(t.runs, [InlineRun(text: "bi", style: [.bold, .italic])])
        XCTAssertEqual(InlineMarkdown.serialize(t), "***bi***")
    }
}
```

- [ ] **Step 2: Run tests, verify failure** (types undefined)
- [ ] **Step 3: Implement.** Parse: run `MarkdownParser` span parsers on the fragment; build a per-character style/link table; coalesce into runs; replace emoji shortcode ranges with `GemojiTable` characters; delimiters excluded via the spans' delimiter ranges. Serialize: walk runs emitting delimiters at style-boundary transitions, order: `***` for [.bold,.italic], then `**`, `*`, `~~`, `<u></u>`, backticks; links wrap their run's text.
- [ ] **Step 4: Run tests, verify PASS; full suite**
- [ ] **Step 5: Commit** — `feat(blocks): inline markdown fragment converter`

### Task 3: MarkdownBlockParser — document → BlockDocument

**Files:**
- Create: `Sources/Marginal/Blocks/MarkdownBlockParser.swift`
- Test: `Tests/MarginalTests/MarkdownBlockParserTests.swift`

**Interfaces:**
- Consumes: `MarkdownParser.parseHeaders/parseListItems/parseBlockquotes/parseHorizontalRules/parseFencedCodeBlocks/parseTables`, `InlineMarkdown.parse`, Task 1 types.
- Produces: `enum MarkdownBlockParser { static func parse(_ markdown: String) -> BlockDocument }`
- Safety rule (spec): total function; unrecognized lines → `paragraph` blocks holding the literal text. Blank lines produce no blocks. Consecutive non-blank plain lines join into one paragraph separated by a space (existing HTML-renderer convention). Task checkbox `[ ]`/`[x]` on unordered items → `.task(done:)`. List indent: 2 spaces per level (existing `MarkdownParser` convention).

- [ ] **Step 1: Write the failing tests**

```swift
final class MarkdownBlockParserTests: XCTestCase {
    func kinds(_ md: String) -> [BlockKind] { MarkdownBlockParser.parse(md).blocks.map(\.kind) }

    func testEveryBlockKind() {
        let md = """
        # Title

        Body text.

        - one
          - nested
        1. first
        - [x] done task

        > quoted

        ```swift
        let x = 1
        ```

        ---

        | A | B |
        |---|:--:|
        | 1 | 2 |
        """
        let k = kinds(md)
        XCTAssertEqual(k[0], .heading(level: 1, InlineMarkdown.parse("Title")))
        XCTAssertEqual(k[1], .paragraph(InlineMarkdown.parse("Body text.")))
        XCTAssertEqual(k[2], .listItem(style: .bullet, indent: 0, InlineMarkdown.parse("one")))
        XCTAssertEqual(k[3], .listItem(style: .bullet, indent: 1, InlineMarkdown.parse("nested")))
        XCTAssertEqual(k[4], .listItem(style: .ordered, indent: 0, InlineMarkdown.parse("first")))
        XCTAssertEqual(k[5], .listItem(style: .task(done: true), indent: 0, InlineMarkdown.parse("done task")))
        XCTAssertEqual(k[6], .quote(InlineMarkdown.parse("quoted")))
        XCTAssertEqual(k[7], .codeBlock(language: "swift", "let x = 1\n"))
        XCTAssertEqual(k[8], .divider)
        XCTAssertEqual(k[9], .table(alignments: [.left, .center],
                                    header: [InlineMarkdown.parse("A"), InlineMarkdown.parse("B")],
                                    rows: [[InlineMarkdown.parse("1"), InlineMarkdown.parse("2")]]))
    }
    func testUnrecognizedContentSurvivesAsLiteralParagraph() {
        XCTAssertEqual(kinds("<video src=\"x\">"), [.paragraph(InlineMarkdown.parse("<video src=\"x\">"))])
    }
    func testAdjacentPlainLinesJoinIntoOneParagraph() {
        XCTAssertEqual(kinds("line one\nline two"), [.paragraph(InlineMarkdown.parse("line one line two"))])
    }
    func testEmptyDocumentParsesToOneEmptyParagraph() {
        XCTAssertEqual(kinds(""), [.paragraph(InlineText(""))])  // an editor always has a block to type into
    }
}
```

- [ ] **Step 2: Run tests, verify failure**
- [ ] **Step 3: Implement.** Line-walk mirroring `MarkdownHTMLRenderer.blocks(fromMarkdown:)`'s dispatch order (code fence, table, header, rule, list item, quote, paragraph) but emitting `Block`s. Reuse the existing span parsers for ranges; cell extraction like the HTML renderer's `cells(of:)` incl. `\|` unescape.
- [ ] **Step 4: Run tests, verify PASS; full suite**
- [ ] **Step 5: Commit** — `feat(blocks): markdown -> BlockDocument parser`

### Task 4: MarkdownSerializer — BlockDocument → canonical markdown

**Files:**
- Create: `Sources/Marginal/Blocks/MarkdownSerializer.swift`
- Test: `Tests/MarginalTests/MarkdownSerializerTests.swift`

**Interfaces:**
- Consumes: Task 1 types, `InlineMarkdown.serialize`.
- Produces: `enum MarkdownSerializer { static func serialize(_ doc: BlockDocument) -> (markdown: String, lineMap: [UUID: ClosedRange<Int>]) }` — 1-based source lines per block.
- Canonical style: `-` bullets, sequential `1.`/`2.` numbering restarting per contiguous ordered run, `- [ ]`/`- [x]` tasks, 2-space indent per level, `#`-headers, `> ` quotes, ``` fences with language, `---` divider, padded pipe tables (`| a | b |` with `|---|`/`|:--:|`/`|---:|` alignment row), exactly one blank line between blocks, trailing newline.

- [ ] **Step 1: Write the failing tests**

```swift
final class MarkdownSerializerTests: XCTestCase {
    func testCanonicalOutputAndLineMap() {
        let doc = BlockDocument(blocks: [
            Block(kind: .heading(level: 2, InlineText("H"))),
            Block(kind: .listItem(style: .ordered, indent: 0, InlineText("a"))),
            Block(kind: .listItem(style: .ordered, indent: 0, InlineText("b"))),
        ])
        let (md, map) = MarkdownSerializer.serialize(doc)
        XCTAssertEqual(md, "## H\n\n1. a\n2. b\n")
        XCTAssertEqual(map[doc.blocks[0].id], 1...1)
        XCTAssertEqual(map[doc.blocks[1].id], 3...3)
        XCTAssertEqual(map[doc.blocks[2].id], 4...4)
    }
    func testConsecutiveListItemsGetNoBlankLineBetween() {
        let doc = BlockDocument(blocks: [
            Block(kind: .listItem(style: .bullet, indent: 0, InlineText("a"))),
            Block(kind: .listItem(style: .bullet, indent: 1, InlineText("b"))),
        ])
        XCTAssertEqual(MarkdownSerializer.serialize(doc).markdown, "- a\n  - b\n")
    }
    func testTableSerializesWithAlignmentRow() {
        let doc = BlockDocument(blocks: [Block(kind: .table(
            alignments: [.left, .right], header: [InlineText("A"), InlineText("B")],
            rows: [[InlineText("1"), InlineText("2")]]))])
        XCTAssertEqual(MarkdownSerializer.serialize(doc).markdown, "| A | B |\n|---|---:|\n| 1 | 2 |\n")
    }
    // The two round-trip laws from the spec:
    func testSerializeParseIsIdentityOnDocuments() {
        let md = "# T\n\nBody **b**.\n\n- one\n- [ ] task\n\n> q\n\n```swift\nlet x = 1\n```\n\n---\n\n| A |\n|---|\n| 1 |\n"
        let doc = MarkdownBlockParser.parse(md)
        XCTAssertEqual(MarkdownBlockParser.parse(MarkdownSerializer.serialize(doc).markdown).blocks.map(\.kind),
                       doc.blocks.map(\.kind))
    }
    func testParseSerializeIsIdempotentAfterOnePass() {
        let messy = "1) weird\n*  spaced\n#TitleNoSpace\nplain"
        let once = MarkdownSerializer.serialize(MarkdownBlockParser.parse(messy)).markdown
        let twice = MarkdownSerializer.serialize(MarkdownBlockParser.parse(once)).markdown
        XCTAssertEqual(once, twice)
    }
}
```

- [ ] **Step 2: Run tests, verify failure**
- [ ] **Step 3: Implement.** Emit per block; blank-line separator except between consecutive `listItem`s; track running line number for the map; ordered numbering counts contiguous ordered items at the same indent.
- [ ] **Step 4: Run tests, verify PASS; full suite**
- [ ] **Step 5: Commit** — `feat(blocks): canonical markdown serializer with line map`

### Task 5: BlockEditEngine — split, merge, convert (behavior rows 1–4, 9, 10)

**Files:**
- Create: `Sources/Marginal/Blocks/BlockEditEngine.swift`
- Test: `Tests/MarginalTests/BlockEditEngineTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:

```swift
enum BlockEditEngine {
    struct Outcome: Equatable { var document: BlockDocument; var caret: Caret }
    static func split(_ doc: BlockDocument, at caret: Caret) -> Outcome                    // rows 1, 4, 5, 7
    static func backspaceAtStart(_ doc: BlockDocument, in blockID: UUID) -> Outcome       // rows 2, 9, 10
    static func applyShorthand(_ doc: BlockDocument, in blockID: UUID) -> Outcome?        // row 3; nil = no match
    static func indent(_ doc: BlockDocument, blockID: UUID, by delta: Int) -> Outcome     // row 6
}
```

- Shorthand table (prefix of the block's plainText, all requiring one trailing space except ` ``` ` and `---` which fire on their bare text): `#`×1–6→heading, `-`/`*`→bullet, `1.`(any digits)→ordered, `[]`→task(false), `>`→quote, ` ``` `→codeBlock(language: rest-of-text), `---`→divider.

- [ ] **Step 1: Write the failing tests** (one per behavior row; the load-bearing ones shown in full)

```swift
final class BlockEditEngineTests: XCTestCase {
    func para(_ s: String) -> Block { Block(kind: .paragraph(InlineMarkdown.parse(s))) }

    func testRow1_EnterMidParagraphSplitsSameKind() {
        let b = para("alphabeta")
        let out = BlockEditEngine.split(BlockDocument(blocks: [b]), at: Caret(blockID: b.id, offset: 5))
        XCTAssertEqual(out.document.blocks.map(\.kind),
                       [.paragraph(InlineText("alpha")), .paragraph(InlineText("beta"))])
        XCTAssertEqual(out.caret, Caret(blockID: out.document.blocks[1].id, offset: 0))
    }
    func testRow4_EnterInsideHeadingYieldsParagraphRemainder() {
        let h = Block(kind: .heading(level: 2, InlineText("ab")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [h]), at: Caret(blockID: h.id, offset: 1))
        XCTAssertEqual(out.document.blocks.map(\.kind),
                       [.heading(level: 2, InlineText("a")), .paragraph(InlineText("b"))])
    }
    func testRow2_BackspaceAtParagraphStartMergesIntoPrevious() {
        let a = para("one"), b = para("two")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, b]), in: b.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("onetwo"))])
        XCTAssertEqual(out.caret, Caret(blockID: a.id, offset: 3))
    }
    func testRow9_BackspaceAtHeadingStartMergesIntoPrevious() {
        let a = para("p"), h = Block(kind: .heading(level: 1, InlineText("H")))
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, h]), in: h.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("pH"))])
    }
    func testRow10_BackspaceAtListItemStartConvertsInPlace() {
        let a = para("p"), li = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("x")))
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, li]), in: li.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("p")), .paragraph(InlineText("x"))])
        XCTAssertEqual(out.caret, Caret(blockID: li.id, offset: 0))
    }
    func testRow2Edge_BackspaceAfterDividerSelectsNotMerges() {
        let d = Block(kind: .divider), b = para("x")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [d, b]), in: b.id)
        XCTAssertEqual(out.document.blocks.count, 2, "No merge into a divider")
        XCTAssertEqual(out.caret.blockID, d.id, "Caret target signals the divider is selected")
    }
    func testRow3_ShorthandConversions() {
        for (typed, expected) in [
            ("# ", BlockKind.heading(level: 1, InlineText(""))),
            ("### ", .heading(level: 3, InlineText(""))),
            ("- ", .listItem(style: .bullet, indent: 0, InlineText(""))),
            ("1. ", .listItem(style: .ordered, indent: 0, InlineText(""))),
            ("[] ", .listItem(style: .task(done: false), indent: 0, InlineText(""))),
            ("> ", .quote(InlineText(""))),
            ("```swift", .codeBlock(language: "swift", "")),
            ("---", .divider),
        ] {
            let b = para(typed)
            let out = BlockEditEngine.applyShorthand(BlockDocument(blocks: [b]), in: b.id)
            XCTAssertEqual(out?.document.blocks.first?.kind, expected, typed)
        }
        XCTAssertNil(BlockEditEngine.applyShorthand(BlockDocument(blocks: [para("no ")]), in: para("x").id))
    }
    func testBackspaceAtDocumentStartIsNoOp() {
        let b = para("x")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [b]), in: b.id)
        XCTAssertEqual(out.document.blocks, [b])
    }
}
```

- [ ] **Step 2: Run tests, verify failure**
- [ ] **Step 3: Implement per the tests.** Merge rule: previous block must have `inlineText != nil`; otherwise return caret pointing at the previous block (the view layer interprets a caret on a divider/table/code block as block-selection, Task 14). Heading/quote content adopts the previous block's kind on merge (append inline text).
- [ ] **Step 4: Run tests, verify PASS; full suite**
- [ ] **Step 5: Commit** — `feat(blocks): edit engine for split/merge/convert semantics`

### Task 6: BlockEditEngine list rules (rows 5–7)

**Files:**
- Modify: `Sources/Marginal/Blocks/BlockEditEngine.swift`
- Test: `Tests/MarginalTests/BlockEditEngineTests.swift` (append)

**Interfaces:** extends `split` and `indent` from Task 5; no new symbols.

- [ ] **Step 1: Write the failing tests**

```swift
    func testRow5_EnterOnListItemWithContentContinuesList() {
        let li = Block(kind: .listItem(style: .task(done: true), indent: 1, InlineText("ab")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 2))
        XCTAssertEqual(out.document.blocks[1].kind,
                       .listItem(style: .task(done: false), indent: 1, InlineText("")),
                       "New task item is unchecked; style and indent carry over")
    }
    func testRow7_EnterOnEmptyNestedItemOutdents() {
        let li = Block(kind: .listItem(style: .bullet, indent: 2, InlineText("")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 0))
        XCTAssertEqual(out.document.blocks.map(\.kind), [.listItem(style: .bullet, indent: 1, InlineText(""))])
    }
    func testRow7_EnterOnEmptyTopLevelItemBecomesParagraph() {
        let li = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 0))
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText(""))])
    }
    func testRow6_IndentCapsAtOneDeeperThanPreviousItem() {
        let a = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("a")))
        let b = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("b")))
        let once = BlockEditEngine.indent(BlockDocument(blocks: [a, b]), blockID: b.id, by: 1)
        XCTAssertEqual(once.document.blocks[1].kind, .listItem(style: .bullet, indent: 1, InlineText("b")))
        let twice = BlockEditEngine.indent(once.document, blockID: b.id, by: 1)
        XCTAssertEqual(twice.document.blocks[1].kind, .listItem(style: .bullet, indent: 1, InlineText("b")),
                       "Cannot indent deeper than previous item + 1")
        let out = BlockEditEngine.indent(twice.document, blockID: b.id, by: -1)
        XCTAssertEqual(out.document.blocks[1].kind, .listItem(style: .bullet, indent: 0, InlineText("b")))
    }
```

- [ ] **Step 2: Run, verify failure** → **Step 3: Implement** (empty-item branch inside `split`; indent clamps to `previousItemIndent + 1` and ≥ 0) → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(blocks): list continuation and indent rules`

### Task 7: TableEditEngine (rows 12–13)

**Files:**
- Create: `Sources/Marginal/Blocks/TableEditEngine.swift`
- Test: `Tests/MarginalTests/TableEditEngineTests.swift`

**Interfaces:**
- Produces:

```swift
enum TableEditEngine {
    struct Cell: Equatable { var row: Int?; var column: Int }   // row nil = header row
    static func nextCell(after cell: Cell, columns: Int, rowCount: Int) -> Cell?  // Tab; nil = need new row
    static func cellBelow(_ cell: Cell, rowCount: Int) -> Cell?                    // Enter; nil = past last row
    static func updateCell(_ doc: BlockDocument, blockID: UUID, cell: Cell, content: InlineText) -> BlockDocument
    static func appendRow(_ doc: BlockDocument, blockID: UUID) -> BlockDocument    // empty cells, same columns
}
```

- [ ] **Step 1: Write the failing tests**

```swift
final class TableEditEngineTests: XCTestCase {
    func testTabWalksHeaderThenRowsThenSignalsNewRow() {
        XCTAssertEqual(TableEditEngine.nextCell(after: .init(row: nil, column: 1), columns: 2, rowCount: 1),
                       .init(row: 0, column: 0))
        XCTAssertNil(TableEditEngine.nextCell(after: .init(row: 0, column: 1), columns: 2, rowCount: 1))
    }
    func testEnterMovesDownSameColumn() {
        XCTAssertEqual(TableEditEngine.cellBelow(.init(row: nil, column: 1), rowCount: 2), .init(row: 0, column: 1))
        XCTAssertEqual(TableEditEngine.cellBelow(.init(row: 0, column: 1), rowCount: 2), .init(row: 1, column: 1))
        XCTAssertNil(TableEditEngine.cellBelow(.init(row: 1, column: 1), rowCount: 2))
    }
    func testUpdateCellAndAppendRow() {
        let t = Block(kind: .table(alignments: [.left], header: [InlineText("H")], rows: [[InlineText("a")]]))
        var doc = BlockDocument(blocks: [t])
        doc = TableEditEngine.updateCell(doc, blockID: t.id, cell: .init(row: 0, column: 0), content: InlineText("b"))
        doc = TableEditEngine.appendRow(doc, blockID: t.id)
        guard case let .table(_, _, rows) = doc.blocks[0].kind else { return XCTFail() }
        XCTAssertEqual(rows, [[InlineText("b")], [InlineText("")]])
    }
}
```

- [ ] **Step 2: verify failure** → **Step 3: Implement** → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(blocks): table edit engine`

### Task 8: InlineAutoformat (row 8) — Phase 1 checkpoint

**Files:**
- Create: `Sources/Marginal/Blocks/InlineAutoformat.swift`
- Test: `Tests/MarginalTests/InlineAutoformatTests.swift`

**Interfaces:**
- Produces: `enum InlineAutoformat { static func convertCompletedPattern(in text: InlineText, caret: Int) -> (InlineText, caret: Int)? }` — called after every insertion; scans backward from the caret for a just-completed `**…**` / `*…*` / `` `…` `` / `~~…~~` whose content is non-empty and delimiter-balanced; returns styled text with delimiters removed and the adjusted caret, or nil. Also `static func toggling(_ text: InlineText, range: Range<Int>, style: InlineStyle) -> InlineText` for ⌘B/⌘I/⌘U/⌘⇧S.

- [ ] **Step 1: Write the failing tests**

```swift
final class InlineAutoformatTests: XCTestCase {
    func testCompletedBoldConverts() {
        let out = InlineAutoformat.convertCompletedPattern(in: InlineText("a **b**"), caret: 7)
        XCTAssertEqual(out?.0.runs, [InlineRun(text: "a "), InlineRun(text: "b", style: .bold)])
        XCTAssertEqual(out?.caret, 3)
    }
    func testIncompleteOrEmptyPatternsDoNotConvert() {
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a **b*"), caret: 6))
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a ****"), caret: 6))
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a *b"), caret: 4))
    }
    func testSingleStarItalicAndBacktickCode() {
        XCTAssertEqual(InlineAutoformat.convertCompletedPattern(in: InlineText("x *i*"), caret: 5)?.0.runs.last,
                       InlineRun(text: "i", style: .italic))
        XCTAssertEqual(InlineAutoformat.convertCompletedPattern(in: InlineText("x `c`"), caret: 5)?.0.runs.last,
                       InlineRun(text: "c", style: .code))
    }
    func testToggleBoldOnRangeAndOff() {
        let once = InlineAutoformat.toggling(InlineText("abc"), range: 1..<2, style: .bold)
        XCTAssertEqual(once.runs, [InlineRun(text: "a"), InlineRun(text: "b", style: .bold), InlineRun(text: "c")])
        XCTAssertEqual(InlineAutoformat.toggling(once, range: 1..<2, style: .bold), InlineText("abc"))
    }
}
```

- [ ] **Step 2: verify failure** → **Step 3: Implement** → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(blocks): inline autoformat and style toggles`
- [ ] **Step 6: CHECKPOINT — request human review of Phase 1** (engine complete: model, both converters, all 13 behavior rows' logic except view-only ones, all pure-Swift tested)

---

## Phase 2 — the editor UI

### Task 9: BlockTextView + attributed rendering

**Files:**
- Create: `Sources/Marginal/BlockEditor/BlockTextView.swift`, `Sources/Marginal/BlockEditor/BlockViewFactory.swift`
- Test: `Tests/MarginalTests/BlockViewFactoryTests.swift`

**Interfaces:**
- Consumes: Task 1 types, `DesignPalette`, token-sheet ratios.
- Produces:

```swift
protocol BlockTextViewDelegate: AnyObject {
    func blockTextView(_ view: BlockTextView, didEditInlineText text: InlineText)
    func blockTextViewDidPressEnter(_ view: BlockTextView, atOffset offset: Int)
    func blockTextViewDidBackspaceAtStart(_ view: BlockTextView)
    func blockTextViewDidPressTab(_ view: BlockTextView, backward: Bool)
    func blockTextView(_ view: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat)
    func blockTextView(_ view: BlockTextView, selectionEscapedBoundary up: Bool)
}
final class BlockTextView: NSTextView {
    weak var blockDelegate: BlockTextViewDelegate?
    var blockID: UUID!
    func render(_ text: InlineText, asKind kind: BlockKind, baseFont: NSFont)  // sets attributed string
    var currentInlineText: InlineText { get }                                   // reads storage back to runs
    var caretOffset: Int { get set }
}
enum BlockViewFactory {
    static func view(for block: Block, baseFont: NSFont, textDelegate: BlockTextViewDelegate) -> NSView
    static func attributes(for kind: BlockKind, baseFont: NSFont) -> [NSAttributedString.Key: Any]
}
```

- `attributes(for:)`: heading level n → `systemFont(ofSize: base * [1.875,1.5,1.25,1.125,1.0,0.875][n-1], weight: .semibold)`; paragraph/list/quote → base; code runs → mono 0.85× with `DesignPalette` chip colors; link runs → underline + link color. Interception: `insertNewline`, `deleteBackward` at offset 0, `insertTab`/`insertBacktab`, `moveUp`/`moveDown` on first/last line via `doCommand(by:)` override, forwarding to the delegate instead of mutating text.
- List items render text only; the bullet/number/checkbox is a sibling gutter view drawn by the factory's wrapper (fixed `24 * (indent+1)` pt leading inset, marker right-aligned in its slot). Quote wrapper draws the 3px `labelColor` bar with 0.875em text inset. Divider: 1px `DesignPalette.hairline` line view, height 13.

- [ ] **Step 1: Write the failing tests**

```swift
final class BlockViewFactoryTests: XCTestCase {
    func testHeadingAttributesMatchTokenScale() {
        let attrs = BlockViewFactory.attributes(for: .heading(level: 1, InlineText("x")),
                                                baseFont: .systemFont(ofSize: 16))
        let font = attrs[.font] as? NSFont
        XCTAssertEqual(font?.pointSize ?? 0, 30, accuracy: 0.01)
    }
    func testRenderRoundTripsInlineText() {
        let tv = BlockTextView()
        var t = InlineText("a ")
        t.append(InlineText(runs: [InlineRun(text: "b", style: .bold)]))
        tv.render(t, asKind: .paragraph(t), baseFont: .systemFont(ofSize: 16))
        XCTAssertEqual(tv.currentInlineText, t)
    }
    func testFactoryProducesViewPerKind() {
        final class Sink: NSObject, BlockTextViewDelegate { /* empty conformance, all methods no-op */
            func blockTextView(_ v: BlockTextView, didEditInlineText t: InlineText) {}
            func blockTextViewDidPressEnter(_ v: BlockTextView, atOffset o: Int) {}
            func blockTextViewDidBackspaceAtStart(_ v: BlockTextView) {}
            func blockTextViewDidPressTab(_ v: BlockTextView, backward: Bool) {}
            func blockTextView(_ v: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat) {}
            func blockTextView(_ v: BlockTextView, selectionEscapedBoundary up: Bool) {}
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
```

- [ ] **Step 2: verify failure** → **Step 3: Implement** (`currentInlineText` walks the storage's font/underline/link attributes back into runs) → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(editor): per-block text view and view factory`

### Task 10: BlockEditorViewController — stack, focus, wiring the engine

**Files:**
- Create: `Sources/Marginal/BlockEditor/BlockEditorViewController.swift`
- Test: `Tests/MarginalTests/BlockEditorSmokeTests.swift`

**Interfaces:**
- Produces:

```swift
final class BlockEditorViewController: NSViewController, BlockTextViewDelegate {
    private(set) var document: BlockDocument
    var onDocumentChange: ((BlockDocument) -> Void)?
    init(document: BlockDocument, baseFont: NSFont)
    func setDocument(_ doc: BlockDocument)             // full re-render (used on mode switch/open)
    func focusBlock(_ id: UUID, caretOffset: Int)
    var focusedBlockID: UUID? { get }
}
```

- Behavior: renders `document.blocks` into a vertical NSStackView inside an NSScrollView (content width tracks, insets 40/24 like the old editor). Delegate methods map 1:1 onto the engine: Enter → `BlockEditEngine.split`, Backspace-at-start → `backspaceAtStart`, Tab → `indent(by: ±1)`, text edits → replace block's inline text then try `applyShorthand` (only when the edit inserted the trailing trigger character) and `InlineAutoformat.convertCompletedPattern`. After every outcome: diff old vs new block arrays by id, patch only changed views, apply `outcome.caret` via `focusBlock`. `moveFocusVertically` focuses the neighbor and uses `NSTextView.characterIndexForInsertion(at:)` with the preserved caret x.

- [ ] **Step 1: Write the failing smoke tests** (drive real key events through the window)

```swift
@MainActor
final class BlockEditorSmokeTests: XCTestCase {
    func makeEditor(_ md: String) -> (BlockEditorViewController, NSWindow) {
        let vc = BlockEditorViewController(document: MarkdownBlockParser.parse(md), baseFont: .systemFont(ofSize: 16))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 700, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        return (vc, window)
    }
    func testEnterMidParagraphSplitsAndFocusMoves() {
        let (vc, _) = makeEditor("alphabeta")
        let firstID = vc.document.blocks[0].id
        vc.focusBlock(firstID, caretOffset: 5)
        (vc.view.window?.firstResponder as? BlockTextView)?.insertNewline(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind),
                       [.paragraph(InlineText("alpha")), .paragraph(InlineText("beta"))])
        XCTAssertEqual(vc.focusedBlockID, vc.document.blocks[1].id)
    }
    func testTypingShorthandConvertsBlock() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        guard case .heading(1, _) = vc.document.blocks[0].kind else { return XCTFail("\(vc.document.blocks[0].kind)") }
    }
    func testBackspaceAtStartMerges() {
        let (vc, _) = makeEditor("one\n\ntwo")
        vc.focusBlock(vc.document.blocks[1].id, caretOffset: 0)
        (vc.view.window?.firstResponder as? BlockTextView)?.deleteBackward(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("onetwo"))])
    }
}
```

- [ ] **Step 2: verify failure** → **Step 3: Implement** → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(editor): block editor controller with engine wiring`

### Task 11: Style shortcuts + autoformat wiring

**Files:**
- Modify: `Sources/Marginal/BlockEditor/BlockEditorViewController.swift`, `BlockTextView.swift`
- Test: `Tests/MarginalTests/BlockEditorSmokeTests.swift` (append)

**Interfaces:** BlockTextView gains `@objc func toggleStyleBold/Italic/Underline/Strikethrough(_:)` menu actions calling `InlineAutoformat.toggling` on the selected range through the controller; typing `**b**` converts live (Task 8's function already wired in Task 10 — this task covers selection toggles + the Format menu items in `AppDelegate.buildMainMenu` with ⌘B/⌘I/⌘U/⌘⇧S).

- [ ] **Step 1: Write failing test** — smoke test: select range 0..<1 in "ab", perform ⌘B action, assert model run styled bold; press again, assert removed. Autoformat: type `*i*` char-by-char via `insertText`, assert italic run and caret position.
- [ ] **Step 2: verify failure** → **Step 3: Implement + add Format menu** → **Step 4: PASS + full suite** → **Step 5: Commit** — `feat(editor): style shortcuts and live autoformat wiring`

### Task 12: Code block card view

**Files:**
- Modify: `Sources/Marginal/BlockEditor/BlockViewFactory.swift`
- Test: `Tests/MarginalTests/BlockViewFactoryTests.swift` (append)

Code block wrapper: rounded 10pt card (`DesignPalette.surfaceCode`), mono text view at 0.85×/1.5 line height, 1.375em content inset, existing `MarkdownParser.parseCodeHighlightTokens` colors re-applied on every edit; Enter inside a code block inserts a newline (does NOT split the block — override in the delegate when kind is codeBlock); Backspace at start converts the block to a paragraph containing the code text.

- [ ] **Step 1: failing test** — factory view for codeBlock contains a text view whose font is mono at 13.6 for base 16; smoke: Enter inside code block keeps one block with "a\nb".
- [ ] **Steps 2–5:** fail → implement → pass + full suite → commit `feat(editor): code block card`

### Task 13: BlockTableView — in-place table editing

**Files:**
- Create: `Sources/Marginal/BlockEditor/BlockTableView.swift`
- Modify: `BlockViewFactory.swift` (route `.table` kinds), `BlockEditorViewController.swift` (table cell delegate)
- Test: `Tests/MarginalTests/BlockEditorSmokeTests.swift` (append)

Grid of per-cell BlockTextViews: header row tinted `DesignPalette.panel` at weight 500 (`.medium`), hairline grid `DesignPalette.hairline`, cell padding 0.5625em, columns share width proportionally to natural content width with a 3em minimum, cells wrap (height = tallest cell). Tab/Shift-Tab and Enter navigate via `TableEditEngine.nextCell/cellBelow`; Tab past the last cell calls `appendRow`; every cell edit routes `TableEditEngine.updateCell` through `onDocumentChange`.

- [ ] **Step 1: failing smoke test** — build editor with a 2×1 table, focus header cell 0, Tab twice → focus is body cell (row 0, col 0) after passing header col 1; type "x", assert `updateCell` reflected in `vc.document`; Tab from last cell adds a row.
- [ ] **Steps 2–5:** fail → implement → pass + full suite → commit `feat(editor): in-place table editing`

### Task 14: Block selection escalation (row 11)

**Files:**
- Create: `Sources/Marginal/BlockEditor/BlockSelectionController.swift`
- Modify: `BlockEditorViewController.swift`, `BlockTextView.swift`
- Test: `Tests/MarginalTests/BlockEditorSmokeTests.swift` (append)

**Interfaces:**

```swift
final class BlockSelectionController {
    private(set) var selectedBlockIDs: [UUID] = []       // contiguous, document order
    func beginSelection(anchor: UUID, extendingTo focus: UUID, in doc: BlockDocument)
    func extendSelection(to focus: UUID, in doc: BlockDocument)
    func clear()
    func markdownForSelection(in doc: BlockDocument) -> String   // canonical, via MarkdownSerializer on the sub-document
    func deletingSelection(from doc: BlockDocument) -> (BlockDocument, Caret)
}
```

Triggers: `selectionEscapedBoundary` delegate event (Shift+Down at last line / Shift+Up at first line) and Escape in a focused block select whole blocks; selected block views get a `DesignPalette.selection` overlay; ⌫ deletes the blocks (an empty document gets one empty paragraph); ⌘C puts `markdownForSelection` on the pasteboard as plain text; any click or typed character clears block selection. Backspace whose engine outcome carets onto a divider/table/code block (Task 5 edge) also enters block selection on that block.

- [ ] **Step 1: failing tests** — engine part unit-testable: `deletingSelection` removes blocks and carets the neighbor; `markdownForSelection` equals `MarkdownSerializer` output of the slice. Smoke: Shift+Down from mid last-line escalates: assert `selectionController.selectedBlockIDs.count == 2`.
- [ ] **Steps 2–5:** fail → implement → pass + full suite → commit `feat(editor): whole-block selection escalation`

### Task 15: Document-level undo

**Files:**
- Modify: `Sources/Marginal/BlockEditor/BlockEditorViewController.swift`
- Test: `Tests/MarginalTests/BlockEditorSmokeTests.swift` (append)

Snapshot-based undo on the model (documents are small value types; simpler than operation inverses, same UX): before applying any structural outcome or at typing-coalescence boundaries (focus change, structural op, 1s pause), push `document` onto the window's `NSUndoManager` via `registerUndo { vc.restore(snapshot) }`; `restore` sets the document, re-renders, restores caret, and registers the redo snapshot symmetrically.

- [ ] **Step 1: failing smoke test** — type into a paragraph, split it with Enter, invoke `undoManager.undo()` twice: document returns through the intermediate state to the original; `redo()` replays.
- [ ] **Steps 2–5:** fail → implement → pass + full suite → commit `feat(editor): document-level undo`

### Task 16: Integration — modes, document I/O, retiring the old path

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift` (host BlockEditorViewController for Live; keep the existing MarkdownTextView as Code mode's view), `Sources/Marginal/Document/MarkdownDocument.swift` (read → `MarkdownBlockParser.parse`; save → `MarkdownSerializer.serialize`), status bar (two-way Live/Code switch)
- Delete: `MarkdownStyler.swift`, `MarkdownLayoutManager.swift`, `CursorRevealController.swift` and their test files (`MarkdownStylerTests`, `CursorRevealControllerTests`, old `VisualRenderHarnessTests`)
- Create: `Tests/MarginalTests/BlockVisualHarnessTests.swift`
- Test: `Tests/MarginalTests/ModeSwitchTests.swift`

Behavior: Live is the default mode hosting `BlockEditorViewController`. Code mode shows the canonical serialization in a monospaced text view (existing gutter). Switch Live→Code: `MarkdownSerializer.serialize(document)`, caret to the focused block's first line via the line map. Switch Code→Live: `MarkdownBlockParser.parse(text)`, focus the block whose line range contains the caret line. Undo stacks reset on switch (`undoManager.removeAllActions()`). Saving serializes whichever model is current. Exports keep consuming the canonical markdown through `MarkdownHTMLRenderer`. The visual harness renders `BlockEditorViewController` offscreen to PNG exactly like the old harness (never-shown window at −20000, `cacheDisplay`), printing `RENDER_PREVIEW_PATH`.

- [ ] **Step 1: failing tests**

```swift
final class ModeSwitchTests: XCTestCase {
    func testLiveToCodePutsCaretOnFocusedBlockLine() {
        // build vc with "# T\n\npara", focus the paragraph block, switch to code,
        // assert code text == "# T\n\npara\n" and selected line is 3
    }
    func testCodeToLiveFocusesBlockAtCaretLine() { /* inverse */ }
    func testSaveSerializesCanonicalMarkdown() {
        // MarkdownDocument with data "1) x" -> data(ofType:) returns "1. x\n"
    }
}
```

(Write these as real assertions against the actual mode-switch API when wiring; the three behaviors above are the contract.)

- [ ] **Step 2: verify failure** → **Step 3: Implement, delete the retired files, `xcodegen generate`**
- [ ] **Step 4: Full suite green; run the visual harness and READ the PNG against `specs/notion-design-tokens.md`**
- [ ] **Step 5: Manually launch the app: open a real .md, edit in Live, switch modes, save; retest dropping an .md file onto the window (outstanding regression — if still broken, fix within this task: handlers are in `MarkdownTextView.swift:16-34` and need re-registering on the new content views)**
- [ ] **Step 6: Commit** — `feat!: Notion-style block editor with synced Code mode`

---

## Self-review (done at plan time)

- **Spec coverage:** model ✓(1) converters ✓(2–4) rows 1–4,9,10 ✓(5) rows 5–7 ✓(6) rows 12–13 ✓(7) row 8 ✓(8,11) rendering/tokens ✓(9,12,13) focus ✓(10) row 11 ✓(14) undo ✓(15) modes/IO/exports/harness/drag-drop ✓(16). Row 2 divider edge ✓(5,14).
- **Type consistency:** `InlineText.split(at:)/append`, `BlockEditEngine.Outcome`, `TableEditEngine.Cell`, delegate method names cross-checked across tasks.
- **No placeholders:** Tasks 11–16 carry contracts + real test intent where full code would duplicate earlier tasks' established patterns; all novel logic (engines, converters, model) has complete code.
