import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayAutomaticRecoveryPolicyTests: XCTestCase {
    func testContentUnavailableWithoutVisibleReadingAllowsSingleAutomaticRecovery() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: false,
            readingError: .contentNotAvailable,
            hasVisibleReading: false,
            automaticRecoveryAttempts: 0
        )

        XCTAssertTrue(policy.isEligibleWhenCooldownCompletes)
        XCTAssertTrue(policy.shouldAttemptAutomaticRecovery)
        XCTAssertEqual(
            policy.cooldownStatusMessage,
            "We'll retry live guidance automatically when the cooldown ends."
        )
        XCTAssertEqual(policy.cooldownStatusSymbol, "clock.badge.checkmark")
    }

    func testPolicyStopsAutomaticRecoveryAfterMaxAttempts() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: false,
            readingError: .contentNotAvailable,
            hasVisibleReading: false,
            automaticRecoveryAttempts: TodayAutomaticRecoveryPolicy.maxAutomaticRecoveryAttempts
        )

        XCTAssertFalse(policy.isEligibleWhenCooldownCompletes)
        XCTAssertFalse(policy.shouldAttemptAutomaticRecovery)
        XCTAssertTrue(policy.hasReachedAutomaticRecoveryLimit)
        XCTAssertEqual(
            policy.cooldownStatusMessage,
            "One automatic retry already ran. Tap Try Again when the cooldown ends."
        )
        XCTAssertEqual(policy.cooldownStatusSymbol, "arrow.clockwise.circle")
    }

    func testPolicySkipsAutomaticRecoveryWhenVisibleReadingExists() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: false,
            readingError: .contentNotAvailable,
            hasVisibleReading: true,
            automaticRecoveryAttempts: 0
        )

        XCTAssertFalse(policy.isEligibleWhenCooldownCompletes)
        XCTAssertFalse(policy.shouldAttemptAutomaticRecovery)
        XCTAssertNil(policy.cooldownStatusSymbol)
    }

    func testPolicySkipsAutomaticRecoveryForNonContentUnavailableErrors() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: false,
            readingError: .networkError,
            hasVisibleReading: false,
            automaticRecoveryAttempts: 0
        )

        XCTAssertFalse(policy.isEligibleWhenCooldownCompletes)
        XCTAssertFalse(policy.shouldAttemptAutomaticRecovery)
    }

    func testPolicySkipsRecoveryWhileLoadingEvenWhenEligible() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: true,
            readingError: .contentNotAvailable,
            hasVisibleReading: false,
            automaticRecoveryAttempts: 0
        )

        XCTAssertTrue(policy.isEligibleWhenCooldownCompletes)
        XCTAssertFalse(policy.shouldAttemptAutomaticRecovery)
    }

    func testPolicyDoesNotShowLimitMessageWhenVisibleReadingExists() {
        let policy = TodayAutomaticRecoveryPolicy(
            isLoading: false,
            readingError: .contentNotAvailable,
            hasVisibleReading: true,
            automaticRecoveryAttempts: TodayAutomaticRecoveryPolicy.maxAutomaticRecoveryAttempts
        )

        XCTAssertTrue(policy.hasReachedAutomaticRecoveryLimit)
        XCTAssertNil(policy.cooldownStatusMessage)
        XCTAssertNil(policy.cooldownStatusSymbol)
    }
}
