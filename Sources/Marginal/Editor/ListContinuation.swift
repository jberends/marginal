import Foundation

/// What pressing Return inside a list item should do -- the behavior every editor has:
/// a list item with content continues the list on the new line (next number for ordered
/// items, an unchecked box for task items); an empty item outdents one level, and an
/// empty top-level item terminates the list, leaving a plain empty line.
enum ListContinuation {

    enum Action: Equatable {
        /// Insert "\n" + this text at the caret.
        case continueList(insertion: String)
        /// Replace the current line's content with this (outdent by one level, or "" to
        /// leave the list entirely).
        case replaceLine(String)
    }

    private static let itemPattern = try! NSRegularExpression(
        pattern: #"^(\s*)([-*+]|\d+\.)( +)(\[[ xX]\] +)?(.*)$"#
    )

    /// One indentation level, matching the parser's two-spaces-per-level convention.
    private static let indentStep = 2

    static func action(forLine line: String) -> Action? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = itemPattern.firstMatch(in: line, range: range) else { return nil }

        func group(_ index: Int) -> String {
            guard let groupRange = Range(match.range(at: index), in: line) else { return "" }
            return String(line[groupRange])
        }

        let indent = group(1)
        let marker = group(2)
        let isTask = !group(4).isEmpty
        let content = group(5)

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: outdent one level, or leave the list at the top level.
            if indent.count >= indentStep {
                return .replaceLine(String(indent.dropFirst(indentStep)) + marker + " " + (isTask ? "[ ] " : ""))
            }
            return .replaceLine("")
        }

        let nextMarker: String
        if marker.hasSuffix("."), let number = Int(marker.dropLast()) {
            nextMarker = "\(number + 1)."
        } else {
            nextMarker = marker
        }
        return .continueList(insertion: indent + nextMarker + " " + (isTask ? "[ ] " : ""))
    }
}
