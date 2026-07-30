import XCTest
@testable import Marginal

final class DocumentStatisticsTests: XCTestCase {

    func testEmptyDocument() {
        let stats = DocumentStatistics.statistics(for: "")
        XCTAssertEqual(stats.wordCount, 0)
        XCTAssertEqual(stats.readingMinutes, 0)
        XCTAssertEqual(stats.statusText, "No words")
    }

    func testCountsWhitespaceSeparatedWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one two three").wordCount, 3)
    }

    func testCollapsesRunsOfWhitespaceAndNewlines() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one   two\n\nthree\tfour\n").wordCount, 4)
    }

    // Markdown markers are punctuation, not words: a "---" rule or a bare "#" adds nothing.
    func testPurePunctuationRunsAreNotWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "# Title\n\n---\n\n**bold**").wordCount, 2)
    }

    func testReadingTimeRoundsUpAndIsAtLeastOneMinuteForAnyWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one").readingMinutes, 1)
        let twoHundredTwenty = Array(repeating: "word", count: 220).joined(separator: " ")
        XCTAssertEqual(DocumentStatistics.statistics(for: twoHundredTwenty).readingMinutes, 1)
        let twoHundredTwentyOne = Array(repeating: "word", count: 221).joined(separator: " ")
        XCTAssertEqual(DocumentStatistics.statistics(for: twoHundredTwentyOne).readingMinutes, 2)
    }

    func testStatusTextSingularAndPlural() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one").statusText, "1 word · 1 min read")
        XCTAssertEqual(DocumentStatistics.statistics(for: "one two").statusText, "2 words · 1 min read")
    }
}
