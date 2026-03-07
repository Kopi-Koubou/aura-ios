import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayLoadErrorBannerPresentationStateTests: XCTestCase {
    func testContentUnavailableWithVisibleReadingUsesInformationalToneDuringCooldown() {
        let state = TodayLoadErrorBannerPresentationState(
            readingError: .contentNotAvailable,
            hasVisibleReading: true,
            isCoolingDown: true,
            cooldownRemainingSeconds: 8
        )

        XCTAssertEqual(state.tone, .informational)
        XCTAssertEqual(state.iconSymbol, "clock.arrow.circlepath")
        XCTAssertEqual(state.title, "Showing saved guidance")
        XCTAssertEqual(
            state.message,
            "Live updates resume in 8s. You can browse saved categories now."
        )
        XCTAssertEqual(state.savedGuidanceRecencyLabel, "Saved recently")
        XCTAssertEqual(
            state.accessibilityValue,
            "Live updates resume in 8s. You can browse saved categories now. Saved guidance is available."
        )
    }

    func testContentUnavailableWithVisibleReadingAfterCooldownShowsRecoveryCopy() {
        let state = TodayLoadErrorBannerPresentationState(
            readingError: .contentNotAvailable,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0
        )

        XCTAssertEqual(state.tone, .informational)
        XCTAssertEqual(
            state.message,
            "Live updates are back. Pull to refresh or tap Retry for a fresh reading."
        )
    }

    func testNetworkErrorWithVisibleReadingKeepsCriticalTone() {
        let state = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0
        )

        XCTAssertEqual(state.tone, .critical)
        XCTAssertEqual(state.iconSymbol, "exclamationmark.triangle.fill")
        XCTAssertEqual(state.title, "Couldn't refresh right now")
        XCTAssertEqual(
            state.message,
            "Showing your latest saved guidance. Check your connection and retry."
        )
    }

    func testContentUnavailableWithoutVisibleReadingUsesCriticalFallbackCopy() {
        let state = TodayLoadErrorBannerPresentationState(
            readingError: .contentNotAvailable,
            hasVisibleReading: false,
            isCoolingDown: true,
            cooldownRemainingSeconds: 8
        )

        XCTAssertEqual(state.tone, .critical)
        XCTAssertEqual(state.title, "Unable to load this reading")
        XCTAssertEqual(
            state.message,
            "Daily content is temporarily unavailable. Try again shortly."
        )
        XCTAssertNil(state.savedGuidanceRecencyLabel)
        XCTAssertEqual(state.accessibilityValue, state.message)
    }

    func testSavedGuidanceRecencyLabelUsesMinutesHoursAndDaysBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let minuteState = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0,
            visibleReadingCreatedAt: now.addingTimeInterval(-15 * 60),
            now: now
        )
        XCTAssertEqual(minuteState.savedGuidanceRecencyLabel, "Saved 15m ago")

        let hourState = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0,
            visibleReadingCreatedAt: now.addingTimeInterval(-3 * 3600),
            now: now
        )
        XCTAssertEqual(hourState.savedGuidanceRecencyLabel, "Saved 3h ago")

        let dayState = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0,
            visibleReadingCreatedAt: now.addingTimeInterval(-49 * 3600),
            now: now
        )
        XCTAssertEqual(dayState.savedGuidanceRecencyLabel, "Saved 2d ago")
    }

    func testSavedGuidanceAccessibilitySummaryPluralization() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        let minuteState = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0,
            visibleReadingCreatedAt: now.addingTimeInterval(-60),
            now: now
        )

        XCTAssertEqual(
            minuteState.accessibilityValue,
            "Showing your latest saved guidance. Check your connection and retry. Saved guidance generated 1 minute ago."
        )

        let dayState = TodayLoadErrorBannerPresentationState(
            readingError: .networkError,
            hasVisibleReading: true,
            isCoolingDown: false,
            cooldownRemainingSeconds: 0,
            visibleReadingCreatedAt: now.addingTimeInterval(-2 * 24 * 3600),
            now: now
        )

        XCTAssertEqual(
            dayState.accessibilityValue,
            "Showing your latest saved guidance. Check your connection and retry. Saved guidance generated 2 days ago."
        )
    }
}
