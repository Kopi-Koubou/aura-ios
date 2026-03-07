import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class PaywallOfferingsPresentationStateTests: XCTestCase {
    func testLoadingStateShowsLoadingFootnoteInsteadOfUnavailableMessage() {
        let state = PaywallOfferingsPresentationState(
            isLoading: true,
            hasAttemptedLoad: false,
            didLastLoadFail: false,
            availablePlanCount: 0,
            totalPlanCount: 2
        )

        XCTAssertTrue(state.showsLoadingPlaceholder)
        XCTAssertFalse(state.showsUnavailableMessage)
        XCTAssertEqual(state.selectorFootnote, "Loading available plans...")
    }

    func testFailedLoadWithoutPlansShowsFailureMessage() {
        let state = PaywallOfferingsPresentationState(
            isLoading: false,
            hasAttemptedLoad: true,
            didLastLoadFail: true,
            availablePlanCount: 0,
            totalPlanCount: 2
        )

        XCTAssertTrue(state.showsUnavailableMessage)
        XCTAssertTrue(state.showsRetryAction)
        XCTAssertEqual(
            state.purchaseUnavailableMessage,
            "Unable to load plans right now. Check your App Store connection and try again."
        )
        XCTAssertEqual(state.selectorFootnote, state.purchaseUnavailableMessage)
    }

    func testPartialAvailabilityShowsRegionalFootnote() {
        let state = PaywallOfferingsPresentationState(
            isLoading: false,
            hasAttemptedLoad: true,
            didLastLoadFail: false,
            availablePlanCount: 1,
            totalPlanCount: 2
        )

        XCTAssertFalse(state.showsUnavailableMessage)
        XCTAssertTrue(state.showsPartialAvailabilityMessage)
        XCTAssertFalse(state.showsRetryAction)
        XCTAssertEqual(
            state.selectorFootnote,
            "Some plan options are temporarily unavailable in your App Store region."
        )
    }

    func testAllPlansAvailableShowsNoFootnote() {
        let state = PaywallOfferingsPresentationState(
            isLoading: false,
            hasAttemptedLoad: true,
            didLastLoadFail: false,
            availablePlanCount: 2,
            totalPlanCount: 2
        )

        XCTAssertFalse(state.showsLoadingPlaceholder)
        XCTAssertFalse(state.showsUnavailableMessage)
        XCTAssertFalse(state.showsPartialAvailabilityMessage)
        XCTAssertFalse(state.showsRetryAction)
        XCTAssertNil(state.selectorFootnote)
    }

    func testUnavailableWithoutFailureStillAllowsRetryAction() {
        let state = PaywallOfferingsPresentationState(
            isLoading: false,
            hasAttemptedLoad: true,
            didLastLoadFail: false,
            availablePlanCount: 0,
            totalPlanCount: 2
        )

        XCTAssertTrue(state.showsUnavailableMessage)
        XCTAssertTrue(state.showsRetryAction)
        XCTAssertEqual(
            state.purchaseUnavailableMessage,
            "Purchases are temporarily unavailable. Check your App Store connection and try again."
        )
    }
}
