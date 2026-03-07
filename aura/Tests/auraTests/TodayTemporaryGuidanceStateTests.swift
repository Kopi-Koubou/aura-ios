import Foundation
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayTemporaryGuidanceStateTests: XCTestCase {
    func testPresentationStateRequiresContentUnavailableAndNoVisibleReading() {
        let eligible = TodayTemporaryGuidancePresentationState(
            hasUser: true,
            isLoading: false,
            hasVisibleReading: false,
            readingError: .contentNotAvailable
        )
        XCTAssertTrue(eligible.shouldShowTemporaryGuidance)

        let hasVisibleReading = TodayTemporaryGuidancePresentationState(
            hasUser: true,
            isLoading: false,
            hasVisibleReading: true,
            readingError: .contentNotAvailable
        )
        XCTAssertFalse(hasVisibleReading.shouldShowTemporaryGuidance)

        let isLoading = TodayTemporaryGuidancePresentationState(
            hasUser: true,
            isLoading: true,
            hasVisibleReading: false,
            readingError: .contentNotAvailable
        )
        XCTAssertFalse(isLoading.shouldShowTemporaryGuidance)

        let networkError = TodayTemporaryGuidancePresentationState(
            hasUser: true,
            isLoading: false,
            hasVisibleReading: false,
            readingError: .networkError
        )
        XCTAssertFalse(networkError.shouldShowTemporaryGuidance)

        let missingUser = TodayTemporaryGuidancePresentationState(
            hasUser: false,
            isLoading: false,
            hasVisibleReading: false,
            readingError: .contentNotAvailable
        )
        XCTAssertFalse(missingUser.shouldShowTemporaryGuidance)
    }

    func testGuidanceStateIsDeterministicForSameInputs() throws {
        let userID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let date = try XCTUnwrap(Self.dayFormatter.date(from: "2026-03-06"))

        let first = TodayTemporaryGuidanceState(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .career,
            date: date
        )
        let second = TodayTemporaryGuidanceState(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .career,
            date: date
        )

        XCTAssertEqual(first.title, "Career Focus")
        XCTAssertEqual(first.subtitle, "Live reading is catching up. Use this focused step for now.")
        XCTAssertEqual(first.bodyText, second.bodyText)
        XCTAssertEqual(first.fortuneScore, second.fortuneScore)
        XCTAssertEqual(first.luckyNumbers, second.luckyNumbers)
        XCTAssertEqual(first.powerColors, second.powerColors)
        XCTAssertTrue((60...95).contains(first.fortuneScore))
        XCTAssertEqual(first.luckyNumbers.count, 5)
        XCTAssertEqual(Set(first.luckyNumbers).count, 5)
        XCTAssertEqual(first.powerColors.count, 3)
    }

    func testGuidanceStateUsesCategorySpecificActionCue() throws {
        let userID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let date = try XCTUnwrap(Self.dayFormatter.date(from: "2026-03-06"))

        let career = TodayTemporaryGuidanceState(
            userID: userID,
            zodiacSign: .scorpio,
            mbtiType: .INFJ,
            category: .career,
            date: date
        )
        let health = TodayTemporaryGuidanceState(
            userID: userID,
            zodiacSign: .scorpio,
            mbtiType: .INFJ,
            category: .health,
            date: date
        )

        XCTAssertNotEqual(career.bodyText, health.bodyText)
        XCTAssertTrue(career.bodyText.contains("high-leverage task"))
        XCTAssertTrue(health.bodyText.contains("non-negotiable reset block"))
    }

    func testQuickSignalTextFormattingIsReadable() throws {
        let userID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let date = try XCTUnwrap(Self.dayFormatter.date(from: "2026-03-06"))

        let state = TodayTemporaryGuidanceState(
            userID: userID,
            zodiacSign: .aries,
            mbtiType: .INTP,
            category: .social,
            date: date
        )

        XCTAssertEqual(
            state.luckyNumbersText,
            state.luckyNumbers.map(String.init).joined(separator: " · ")
        )
        XCTAssertEqual(
            state.luckyNumbersAccessibilityText,
            state.luckyNumbers.map(String.init).joined(separator: ", ")
        )
        XCTAssertEqual(
            state.powerColorsText,
            state.powerColors.joined(separator: ", ")
        )
        XCTAssertEqual(
            state.powerColorsAccessibilityText,
            state.powerColors.joined(separator: ", ")
        )
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
