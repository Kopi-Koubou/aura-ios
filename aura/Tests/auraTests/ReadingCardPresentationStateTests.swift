import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class ReadingCardPresentationStateTests: XCTestCase {
    func testCollapsedStandardTypeUsesSixLinePreview() {
        let state = ReadingCardPresentationState(
            isExpanded: false,
            contentWordCount: 120,
            dynamicTypeSize: .large
        )

        XCTAssertTrue(state.showsExpansionControl)
        XCTAssertFalse(state.usesStackedHeaderLayout)
        XCTAssertEqual(state.lineLimit, 6)
        XCTAssertTrue(state.showsCollapsedFadeOverlay)
        XCTAssertEqual(state.toggleButtonTitle, "Read full reading")
        XCTAssertEqual(state.toggleButtonIcon, "chevron.down")
    }

    func testCollapsedAccessibilityTypeUsesEightLinePreview() {
        let state = ReadingCardPresentationState(
            isExpanded: false,
            contentWordCount: 120,
            dynamicTypeSize: .accessibility3
        )

        XCTAssertTrue(state.showsExpansionControl)
        XCTAssertTrue(state.usesStackedHeaderLayout)
        XCTAssertEqual(state.lineLimit, 8)
        XCTAssertTrue(state.showsCollapsedFadeOverlay)
    }

    func testExpandedStateRemovesLineLimitAndFade() {
        let state = ReadingCardPresentationState(
            isExpanded: true,
            contentWordCount: 120,
            dynamicTypeSize: .large
        )

        XCTAssertTrue(state.showsExpansionControl)
        XCTAssertNil(state.lineLimit)
        XCTAssertFalse(state.showsCollapsedFadeOverlay)
        XCTAssertEqual(state.toggleButtonTitle, "Show less")
        XCTAssertEqual(state.toggleButtonIcon, "chevron.up")
    }

    func testShortContentSkipsExpansionControl() {
        let state = ReadingCardPresentationState(
            isExpanded: false,
            contentWordCount: 20,
            dynamicTypeSize: .large
        )

        XCTAssertFalse(state.showsExpansionControl)
        XCTAssertNil(state.lineLimit)
        XCTAssertFalse(state.showsCollapsedFadeOverlay)
    }
}
