import Foundation

/// Word count and reading time for the status bar in Preview mode, where the caret-based
/// breadcrumb and "L · C" readout have nothing to report.
struct DocumentStatistics: Equatable {

    /// Average adult silent-reading speed for prose, in words per minute. 220 is the midpoint
    /// of the commonly cited 200–250 range.
    static let wordsPerMinute = 220

    let wordCount: Int
    let readingMinutes: Int

    /// Counts whitespace-separated runs that contain at least one letter or digit, so markdown
    /// punctuation ("---", "#", "**") never inflates the count.
    static func statistics(for markdown: String) -> DocumentStatistics {
        let words = markdown
            .split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
        let minutes = words == 0 ? 0 : Int(ceil(Double(words) / Double(wordsPerMinute)))
        return DocumentStatistics(wordCount: words, readingMinutes: minutes)
    }

    var statusText: String {
        guard wordCount > 0 else { return "No words" }
        let wordLabel = wordCount == 1 ? "1 word" : "\(wordCount) words"
        return "\(wordLabel) · \(readingMinutes) min read"
    }
}
