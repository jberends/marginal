import Foundation

struct InlineStyle: OptionSet, Equatable, Hashable {
    let rawValue: Int
    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let strikethrough = InlineStyle(rawValue: 1 << 2)
    static let underline = InlineStyle(rawValue: 1 << 3)
    static let code = InlineStyle(rawValue: 1 << 4)
}

struct InlineRun: Equatable {
    var text: String
    var style: InlineStyle = []
    var linkURL: String? = nil
}

struct InlineText: Equatable {
    var runs: [InlineRun]

    init(_ plain: String = "") {
        // one unstyled run ([] when plain is empty)
        if plain.isEmpty {
            self.runs = []
        } else {
            self.runs = [InlineRun(text: plain)]
        }
    }

    init(runs: [InlineRun]) {
        // normalizes: drops empty runs, merges equal-styled neighbors
        var normalized: [InlineRun] = []

        for run in runs {
            if run.text.isEmpty {
                continue  // drop empty runs
            }

            if let lastIndex = normalized.indices.last,
               normalized[lastIndex].style == run.style,
               normalized[lastIndex].linkURL == run.linkURL {
                // merge equal-styled neighbors
                normalized[lastIndex].text.append(contentsOf: run.text)
            } else {
                normalized.append(run)
            }
        }

        self.runs = normalized
    }

    var plainText: String {
        return runs.map { $0.text }.joined()
    }

    var length: Int {
        return plainText.count
    }

    func split(at offset: Int) -> (InlineText, InlineText) {
        guard offset > 0 && offset < length else {
            if offset <= 0 {
                return (InlineText(""), self)
            } else {
                return (self, InlineText(""))
            }
        }

        var leftRuns: [InlineRun] = []
        var rightRuns: [InlineRun] = []
        var currentCount = 0

        for run in runs {
            let runLength = run.text.count
            let runEnd = currentCount + runLength

            if runEnd <= offset {
                // entire run goes to left
                leftRuns.append(run)
            } else if currentCount >= offset {
                // entire run goes to right
                rightRuns.append(run)
            } else {
                // run is split
                let splitIndex = run.text.index(run.text.startIndex, offsetBy: offset - currentCount)
                let leftPart = String(run.text[..<splitIndex])
                let rightPart = String(run.text[splitIndex...])

                leftRuns.append(InlineRun(text: leftPart, style: run.style, linkURL: run.linkURL))
                rightRuns.append(InlineRun(text: rightPart, style: run.style, linkURL: run.linkURL))
            }

            currentCount = runEnd
        }

        return (InlineText(runs: leftRuns), InlineText(runs: rightRuns))
    }

    mutating func append(_ other: InlineText) {
        let combined = self.runs + other.runs
        let normalized = InlineText(runs: combined)
        self.runs = normalized.runs
    }
}

enum ListStyle: Equatable {
    case bullet
    case ordered
    case task(done: Bool)
}

enum BlockKind: Equatable {
    case paragraph(InlineText)
    case heading(level: Int, InlineText)
    case listItem(style: ListStyle, indent: Int, InlineText)
    case quote(InlineText)
    case codeBlock(language: String?, String)
    case table(alignments: [TableAlignment], header: [InlineText], rows: [[InlineText]])
    case divider

    var inlineText: InlineText? {
        switch self {
        case .paragraph(let text):
            return text
        case .heading(_, let text):
            return text
        case .listItem(_, _, let text):
            return text
        case .quote(let text):
            return text
        case .codeBlock, .table, .divider:
            return nil
        }
    }

    func replacingInlineText(_ t: InlineText) -> BlockKind {
        switch self {
        case .paragraph:
            return .paragraph(t)
        case .heading(let level, _):
            return .heading(level: level, t)
        case .listItem(let style, let indent, _):
            return .listItem(style: style, indent: indent, t)
        case .quote:
            return .quote(t)
        case .codeBlock, .table, .divider:
            return self
        }
    }
}

struct Block: Equatable, Identifiable {
    let id: UUID
    var kind: BlockKind

    init(kind: BlockKind) {
        self.id = UUID()
        self.kind = kind
    }
}

struct BlockDocument: Equatable {
    var blocks: [Block]

    func index(of id: UUID) -> Int? {
        return blocks.firstIndex { $0.id == id }
    }

    subscript(id: UUID) -> Block? {
        guard let index = index(of: id) else { return nil }
        return blocks[index]
    }
}

struct Caret: Equatable {
    var blockID: UUID
    var offset: Int
}
