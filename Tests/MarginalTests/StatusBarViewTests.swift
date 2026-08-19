// Tests/MarginalTests/StatusBarViewTests.swift
import XCTest
import AppKit
@testable import Marginal

@MainActor
final class StatusBarViewTests: XCTestCase {

    func testDefaultsToCursorPosition() {
        XCTAssertFalse(StatusBarView(frame: .zero).showsCounts)
    }

    func testClickingTheBarAndSettingThePropertyReachTheSameState() {
        let bar = StatusBarView(frame: .zero)
        let click = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
        bar.mouseDown(with: click)
        XCTAssertTrue(bar.showsCounts, "a click must flip the same state the menu item sets")

        bar.showsCounts = false
        XCTAssertFalse(bar.showsCounts)
    }
}
