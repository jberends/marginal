import XCTest
@testable import Marginal

final class FontSizingTests: XCTestCase {

    func testIncreaseAddsOnePoint() {
        XCTAssertEqual(FontSizing.increased(from: 14), 15)
    }

    func testIncreaseClampsAtMaximum() {
        XCTAssertEqual(FontSizing.increased(from: FontSizing.maximumPointSize), FontSizing.maximumPointSize)
    }

    func testDecreaseSubtractsOnePoint() {
        XCTAssertEqual(FontSizing.decreased(from: 14), 13)
    }

    func testDecreaseClampsAtMinimum() {
        XCTAssertEqual(FontSizing.decreased(from: FontSizing.minimumPointSize), FontSizing.minimumPointSize)
    }
}
