import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class PaywallPlanCardPresentationStateTests: XCTestCase {
    func testStandardDynamicTypeUsesHorizontalPlanLayout() {
        let state = PaywallPlanCardPresentationState(dynamicTypeSize: .large)

        XCTAssertFalse(state.usesStackedLayout)
        XCTAssertFalse(state.usesStackedBadgeLayout)
    }

    func testAccessibilityDynamicTypeUsesStackedPlanLayout() {
        let state = PaywallPlanCardPresentationState(dynamicTypeSize: .accessibility2)

        XCTAssertTrue(state.usesStackedLayout)
        XCTAssertTrue(state.usesStackedBadgeLayout)
    }

    func testExtraLargeDynamicTypeRemainsHorizontalUntilAccessibilitySizes() {
        let state = PaywallPlanCardPresentationState(dynamicTypeSize: .xxxLarge)

        XCTAssertFalse(state.usesStackedLayout)
        XCTAssertFalse(state.usesStackedBadgeLayout)
    }
}
