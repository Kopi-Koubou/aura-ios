import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class TodayAutomaticLoadPolicyTests: XCTestCase {
    func testCoolingDownWithContentUnavailableUsesCacheOnlyMode() {
        let policy = TodayAutomaticLoadPolicy(
            isCoolingDown: true,
            readingError: .contentNotAvailable
        )

        XCTAssertEqual(policy.categoryLoadBehavior, .cacheOnly)
        XCTAssertFalse(policy.allowsAutomaticCategoryLoad)
    }

    func testCoolingDownWithNonContentErrorKeepsFullLoadMode() {
        let policy = TodayAutomaticLoadPolicy(
            isCoolingDown: true,
            readingError: .networkError
        )

        XCTAssertEqual(policy.categoryLoadBehavior, .fullLoad)
        XCTAssertTrue(policy.allowsAutomaticCategoryLoad)
    }

    func testCoolingDownWithoutErrorKeepsFullLoadMode() {
        let policy = TodayAutomaticLoadPolicy(
            isCoolingDown: true,
            readingError: nil
        )

        XCTAssertEqual(policy.categoryLoadBehavior, .fullLoad)
        XCTAssertTrue(policy.allowsAutomaticCategoryLoad)
    }

    func testNotCoolingDownAlwaysUsesFullLoadMode() {
        let policy = TodayAutomaticLoadPolicy(
            isCoolingDown: false,
            readingError: .contentNotAvailable
        )

        XCTAssertEqual(policy.categoryLoadBehavior, .fullLoad)
        XCTAssertTrue(policy.allowsAutomaticCategoryLoad)
    }
}
