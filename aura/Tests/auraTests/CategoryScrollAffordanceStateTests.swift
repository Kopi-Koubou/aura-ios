import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class CategoryScrollAffordanceStateTests: XCTestCase {
    func testNoOverflowHidesBothAffordances() {
        var state = CategoryScrollAffordanceState()
        state.updateViewportWidth(300)
        state.updateContentWidth(307)
        state.updateContentMinX(0)

        XCTAssertFalse(state.hasOverflow)
        XCTAssertFalse(state.showsLeadingAffordance)
        XCTAssertFalse(state.showsTrailingAffordance)
    }

    func testOverflowShowsTrailingAffordanceAtStart() {
        var state = CategoryScrollAffordanceState()
        state.updateViewportWidth(200)
        state.updateContentWidth(380)
        state.updateContentMinX(0)

        XCTAssertTrue(state.hasOverflow)
        XCTAssertFalse(state.showsLeadingAffordance)
        XCTAssertTrue(state.showsTrailingAffordance)
    }

    func testOverflowShowsBothAffordancesInMiddle() {
        var state = CategoryScrollAffordanceState()
        state.updateViewportWidth(200)
        state.updateContentWidth(380)
        state.updateContentMinX(-90)

        XCTAssertTrue(state.showsLeadingAffordance)
        XCTAssertTrue(state.showsTrailingAffordance)
    }

    func testOverflowHidesTrailingAffordanceNearEnd() {
        var state = CategoryScrollAffordanceState()
        state.updateViewportWidth(200)
        state.updateContentWidth(380)
        state.updateContentMinX(-180)

        XCTAssertTrue(state.showsLeadingAffordance)
        XCTAssertFalse(state.showsTrailingAffordance)
    }
}
