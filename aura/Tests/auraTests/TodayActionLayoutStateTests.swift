import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayActionLayoutStateTests: XCTestCase {
    func testStandardDynamicTypeKeepsCompactActionSizing() {
        let state = TodayActionLayoutState(dynamicTypeSize: .large)

        XCTAssertFalse(state.usesAccessibilityLayout)
        XCTAssertEqual(state.primaryButtonMinHeight, 48)
        XCTAssertEqual(state.primaryButtonVerticalPadding, 0)
        XCTAssertEqual(state.statusBannerMinHeight, 32)
        XCTAssertEqual(state.statusBannerVerticalPadding, 0)
        XCTAssertEqual(state.compactPillMinHeight, 28)
        XCTAssertEqual(state.compactPillVerticalPadding, 0)
        XCTAssertEqual(state.bannerButtonMinHeight, 30)
        XCTAssertEqual(state.bannerButtonVerticalPadding, 0)
        XCTAssertEqual(state.retryButtonLineLimit, 1)
        XCTAssertEqual(state.retryButtonMinimumScaleFactor, 0.92)
    }

    func testAccessibilityDynamicTypeExpandsActionSizing() {
        let state = TodayActionLayoutState(dynamicTypeSize: .accessibility3)

        XCTAssertTrue(state.usesAccessibilityLayout)
        XCTAssertEqual(state.primaryButtonMinHeight, 56)
        XCTAssertEqual(state.primaryButtonVerticalPadding, 4)
        XCTAssertEqual(state.statusBannerMinHeight, 40)
        XCTAssertEqual(state.statusBannerVerticalPadding, 2)
        XCTAssertEqual(state.compactPillMinHeight, 34)
        XCTAssertEqual(state.compactPillVerticalPadding, 1)
        XCTAssertEqual(state.bannerButtonMinHeight, 36)
        XCTAssertEqual(state.bannerButtonVerticalPadding, 1)
        XCTAssertNil(state.retryButtonLineLimit)
        XCTAssertEqual(state.retryButtonMinimumScaleFactor, 1)
    }
}
