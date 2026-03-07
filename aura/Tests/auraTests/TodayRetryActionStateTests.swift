import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayRetryActionStateTests: XCTestCase {
    func testIdleStateEnablesRetryActions() {
        let state = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: 0)

        XCTAssertFalse(state.isDisabled)
        XCTAssertTrue(state.allowsManualRefresh)
        XCTAssertFalse(state.showsProgress)
        XCTAssertEqual(state.bannerButtonTitle, "Retry")
        XCTAssertEqual(state.cardButtonTitle, "Try Again")
        XCTAssertEqual(state.cardButtonSymbol, "arrow.clockwise")
        XCTAssertEqual(
            state.bannerAccessibilityHint,
            "Attempts to load today's full reading again"
        )
    }

    func testLoadingStateShowsProgressCopyAndBlocksManualRefresh() {
        let state = TodayRetryActionState(isLoading: true, cooldownRemainingSeconds: 0)

        XCTAssertTrue(state.isDisabled)
        XCTAssertFalse(state.allowsManualRefresh)
        XCTAssertTrue(state.showsProgress)
        XCTAssertEqual(state.bannerButtonTitle, "Retrying...")
        XCTAssertEqual(state.cardButtonTitle, "Trying Again...")
        XCTAssertEqual(state.cardButtonSymbol, "arrow.clockwise")
        XCTAssertEqual(state.cardAccessibilityHint, "Retry in progress")
    }

    func testCooldownStateDisablesRetryWithCountdownCopy() {
        let state = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: 8)

        XCTAssertTrue(state.isDisabled)
        XCTAssertFalse(state.allowsManualRefresh)
        XCTAssertFalse(state.showsProgress)
        XCTAssertEqual(state.bannerButtonTitle, "Wait 8s")
        XCTAssertEqual(state.cardButtonTitle, "Try Again in 8s")
        XCTAssertEqual(state.cardButtonSymbol, "hourglass")
        XCTAssertEqual(
            state.cardAccessibilityHint,
            "Retry is temporarily disabled. 8 seconds remaining."
        )
        XCTAssertEqual(
            state.cooldownMessage,
            "We're giving live content a brief reset. Try again in 8 seconds."
        )
        XCTAssertEqual(state.cooldownProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(
            state.cooldownAccessibilityValue,
            "0% complete, 8 seconds remaining."
        )
        XCTAssertEqual(state.cooldownProgressPercent, 0)
        XCTAssertEqual(state.cooldownTimerLabel, "00:08")
    }

    func testCooldownDurationRemainsStable() {
        XCTAssertEqual(TodayRetryActionState.cooldownDurationSeconds, 8)
        XCTAssertEqual(TodayRetryActionState.cooldownNanoseconds, 8_000_000_000)
    }

    func testCooldownProgressNormalizesElapsedTimeAndClampsBounds() {
        let halfElapsed = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: 4)
        XCTAssertEqual(halfElapsed.cooldownProgress, 0.5, accuracy: 0.0001)

        let aboveRange = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: 12)
        XCTAssertEqual(aboveRange.cooldownProgress, 0, accuracy: 0.0001)
        XCTAssertEqual(aboveRange.cooldownTimerLabel, "00:08")

        let complete = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: -2)
        XCTAssertEqual(complete.cooldownProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(complete.cooldownProgressPercent, 100)
        XCTAssertEqual(complete.cooldownAccessibilityValue, "Cooldown complete.")
        XCTAssertEqual(complete.cooldownTimerLabel, "00:00")
    }

    func testCooldownAccessibilitySummaryIncludesAutoRecoveryMessageWhenProvided() {
        let state = TodayRetryActionState(isLoading: false, cooldownRemainingSeconds: 4)
        let message = "We'll retry live guidance automatically when the cooldown ends."

        XCTAssertEqual(
            state.cooldownAccessibilitySummary(autoRecoveryMessage: message),
            "50% complete, 4 seconds remaining. We'll retry live guidance automatically when the cooldown ends."
        )
        XCTAssertEqual(
            state.cooldownAccessibilitySummary(autoRecoveryMessage: nil),
            "50% complete, 4 seconds remaining."
        )
    }
}
