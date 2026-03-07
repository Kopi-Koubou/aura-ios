import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class CategorySelectorPresentationStateTests: XCTestCase {
    func testStandardDynamicTypeKeepsScrollableLayout() {
        let state = CategorySelectorPresentationState(dynamicTypeSize: .large)

        XCTAssertFalse(state.usesStackedLayout)
        XCTAssertEqual(state.containerAccessibilityHint, "Swipe horizontally to browse categories.")
    }

    func testAccessibilityDynamicTypeUsesStackedLayout() {
        let state = CategorySelectorPresentationState(dynamicTypeSize: .accessibility3)

        XCTAssertTrue(state.usesStackedLayout)
        XCTAssertEqual(state.containerAccessibilityHint, "Browse categories in a vertical list.")
    }
}
