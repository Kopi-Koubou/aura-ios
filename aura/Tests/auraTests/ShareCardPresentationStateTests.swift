import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class ShareCardPresentationStateTests: XCTestCase {
    func testDisplayedPowerColorsSanitizesDeduplicatesAndCapsAtThree() {
        let state = ShareCardPresentationState(
            powerColors: [" Gold ", "", "gold", "Sea Green", "Lavender", "Coral"],
            fortuneScore: 82
        )

        XCTAssertEqual(state.displayedPowerColors, ["Gold", "Sea Green", "Lavender"])
    }

    func testDisplayedPowerColorsReturnsEmptyWhenInputIsWhitespaceOnly() {
        let state = ShareCardPresentationState(
            powerColors: [" ", "\n", "\t"],
            fortuneScore: 82
        )

        XCTAssertTrue(state.displayedPowerColors.isEmpty)
    }

    func testHighFortuneUsesStrongMomentumLabel() {
        let state = ShareCardPresentationState(powerColors: [], fortuneScore: 90)
        XCTAssertEqual(state.fortuneMomentumLabel, "Strong momentum")
    }

    func testMidAndLowFortuneUseExpectedMomentumLabels() {
        let steadyState = ShareCardPresentationState(powerColors: [], fortuneScore: 70)
        let reflectiveState = ShareCardPresentationState(powerColors: [], fortuneScore: 69)

        XCTAssertEqual(steadyState.fortuneMomentumLabel, "Steady momentum")
        XCTAssertEqual(reflectiveState.fortuneMomentumLabel, "Reflective momentum")
    }
}
