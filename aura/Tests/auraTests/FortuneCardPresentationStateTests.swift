import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class FortuneCardPresentationStateTests: XCTestCase {
    func testStandardDynamicTypeUsesHorizontalLayouts() {
        let state = FortuneCardPresentationState(dynamicTypeSize: .large)

        XCTAssertFalse(state.usesStackedHeaderLayout)
        XCTAssertFalse(state.usesStackedDetailLayout)
    }

    func testAccessibilityDynamicTypeUsesStackedLayouts() {
        let state = FortuneCardPresentationState(dynamicTypeSize: .accessibility2)

        XCTAssertTrue(state.usesStackedHeaderLayout)
        XCTAssertTrue(state.usesStackedDetailLayout)
    }
}
