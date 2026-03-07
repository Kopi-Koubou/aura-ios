import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodaySharePresentationStateTests: XCTestCase {
    func testInitialStateIsIdleWithoutFailure() {
        let state = TodaySharePresentationState()

        XCTAssertFalse(state.isPreparing)
        XCTAssertNil(state.failureMessage)
        XCTAssertEqual(state.buttonTitle, "Share Reading")
    }

    func testBeginPreparingClearsFailureAndUpdatesButtonCopy() {
        var state = TodaySharePresentationState()
        state.finish(preparedItemCount: 0)

        state.beginPreparing()

        XCTAssertTrue(state.isPreparing)
        XCTAssertNil(state.failureMessage)
        XCTAssertEqual(state.buttonTitle, "Preparing...")
    }

    func testFinishWithoutItemsShowsFailureMessage() {
        var state = TodaySharePresentationState()
        state.beginPreparing()

        state.finish(preparedItemCount: 0)

        XCTAssertFalse(state.isPreparing)
        XCTAssertEqual(
            state.failureMessage,
            "Couldn't prepare this share card. Please try again."
        )
    }

    func testFinishWithItemsReturnsToIdleWithoutFailure() {
        var state = TodaySharePresentationState()
        state.beginPreparing()

        state.finish(preparedItemCount: 2)

        XCTAssertFalse(state.isPreparing)
        XCTAssertNil(state.failureMessage)
        XCTAssertEqual(state.buttonTitle, "Share Reading")
    }
}
