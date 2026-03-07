import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayReadingLoadStateTests: XCTestCase {
    func testStaleRequestFinishDoesNotClearActiveLoadingState() {
        var state = TodayReadingLoadState()
        let firstRequest = state.begin()
        let secondRequest = state.begin()

        state.finish(firstRequest)

        XCTAssertTrue(state.isLoading)
        XCTAssertEqual(state.activeRequestID, secondRequest)

        state.finish(secondRequest)

        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.activeRequestID)
    }

    func testShouldApplyRequiresActiveRequestMatchingCategoryAndNoCancellation() {
        var state = TodayReadingLoadState()
        let activeRequest = state.begin()
        let staleRequest = UUID()

        XCTAssertTrue(
            state.shouldApply(
                activeRequest,
                completedCategory: .career,
                selectedCategory: .career,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            state.shouldApply(
                staleRequest,
                completedCategory: .career,
                selectedCategory: .career,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            state.shouldApply(
                activeRequest,
                completedCategory: .career,
                selectedCategory: .love,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            state.shouldApply(
                activeRequest,
                completedCategory: .career,
                selectedCategory: .career,
                isCancelled: true
            )
        )
    }

    func testFinishedActiveRequestCannotApplyResultAnymore() {
        var state = TodayReadingLoadState()
        let requestID = state.begin()

        state.finish(requestID)

        XCTAssertFalse(
            state.shouldApply(
                requestID,
                completedCategory: .career,
                selectedCategory: .career,
                isCancelled: false
            )
        )
    }

    func testPresentationStateShowsInlineRefreshForSelectedCategoryReading() {
        let state = TodayReadingPresentationState(
            selectedCategory: .career,
            currentReadingCategory: .career,
            isLoading: true
        )

        XCTAssertTrue(state.selectedReadingIsVisible)
        XCTAssertTrue(state.showsRefreshIndicator)
        XCTAssertFalse(state.showsLoadingSkeleton)
    }

    func testPresentationStateShowsSkeletonWhenLoadingDifferentCategory() {
        let state = TodayReadingPresentationState(
            selectedCategory: .love,
            currentReadingCategory: .career,
            isLoading: true
        )

        XCTAssertFalse(state.selectedReadingIsVisible)
        XCTAssertFalse(state.showsRefreshIndicator)
        XCTAssertTrue(state.showsLoadingSkeleton)
    }
}
