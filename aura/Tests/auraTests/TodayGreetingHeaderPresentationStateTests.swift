import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayGreetingHeaderPresentationStateTests: XCTestCase {
    func testStandardDynamicTypeKeepsInlineLayoutForFreeUser() {
        let state = TodayGreetingHeaderPresentationState(dynamicTypeSize: .large, isPremium: false)

        XCTAssertTrue(state.showsPremiumButton)
        XCTAssertFalse(state.usesStackedLayout)
    }

    func testAccessibilityDynamicTypeStacksLayoutForFreeUser() {
        let state = TodayGreetingHeaderPresentationState(
            dynamicTypeSize: .accessibility3,
            isPremium: false
        )

        XCTAssertTrue(state.showsPremiumButton)
        XCTAssertTrue(state.usesStackedLayout)
    }

    func testPremiumUserHidesUpsellButtonEvenAtAccessibilitySizes() {
        let state = TodayGreetingHeaderPresentationState(
            dynamicTypeSize: .accessibility5,
            isPremium: true
        )

        XCTAssertFalse(state.showsPremiumButton)
        XCTAssertFalse(state.usesStackedLayout)
    }
}
