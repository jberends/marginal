import XCTest
@testable import Marginal

final class ListContinuationTests: XCTestCase {

    func testBulletItemContinuesWithSameMarker() {
        XCTAssertEqual(ListContinuation.action(forLine: "- first"), .continueList(insertion: "- "))
        XCTAssertEqual(ListContinuation.action(forLine: "* starred"), .continueList(insertion: "* "))
    }

    func testOrderedItemContinuesWithNextNumber() {
        XCTAssertEqual(ListContinuation.action(forLine: "3. third"), .continueList(insertion: "4. "))
    }

    func testTaskItemContinuesWithUncheckedBox() {
        XCTAssertEqual(ListContinuation.action(forLine: "- [x] done"), .continueList(insertion: "- [ ] "))
        XCTAssertEqual(ListContinuation.action(forLine: "- [ ] open"), .continueList(insertion: "- [ ] "))
    }

    func testNestedItemKeepsItsIndent() {
        XCTAssertEqual(ListContinuation.action(forLine: "  - nested"), .continueList(insertion: "  - "))
    }

    func testEmptyTopLevelItemLeavesTheList() {
        XCTAssertEqual(ListContinuation.action(forLine: "- "), .replaceLine(""))
        XCTAssertEqual(ListContinuation.action(forLine: "1. "), .replaceLine(""))
        XCTAssertEqual(ListContinuation.action(forLine: "- [ ] "), .replaceLine(""))
    }

    func testEmptyNestedItemOutdentsOneLevel() {
        XCTAssertEqual(ListContinuation.action(forLine: "  - "), .replaceLine("- "))
        XCTAssertEqual(ListContinuation.action(forLine: "    - [ ] "), .replaceLine("  - [ ] "))
    }

    func testPlainTextIsNotAListItem() {
        XCTAssertNil(ListContinuation.action(forLine: "Just a paragraph."))
        XCTAssertNil(ListContinuation.action(forLine: ""))
        XCTAssertNil(ListContinuation.action(forLine: "-not a list"))
    }
}
