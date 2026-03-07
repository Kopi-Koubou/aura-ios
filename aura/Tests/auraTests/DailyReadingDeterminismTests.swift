import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class DailyReadingDeterminismTests: XCTestCase {
    func testSeededRandomGeneratorMatchesEdgeSequence() {
        var generator = SeededRandomGenerator(seed: "11111111-1111-1111-1111-111111111111|aries|2026-03-05")

        let fortuneScore = generator.randomInt(in: 60...95)
        let luckyNumbers = generator.randomUniqueInts(count: 5, in: 1...99).sorted()
        let powerColors = generator.randomPowerColors()

        XCTAssertEqual(fortuneScore, 76)
        XCTAssertEqual(luckyNumbers, [6, 17, 35, 70, 83])
        XCTAssertEqual(powerColors, ["Amber", "Crimson", "Teal"])
    }

    func testDailyReadingKeepsDeterministicExtrasStableForSameUserAndDay() {
        let birthdate = Date(timeIntervalSince1970: 915_148_800) // 1999-01-01
        let user = UserProfile(name: "Deterministic User", birthdate: birthdate, mbtiType: .INTJ)
        user.id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        let first = DailyReading(
            user: user,
            category: .career,
            content: "First content body",
            isPremium: false
        )
        let second = DailyReading(
            user: user,
            category: .career,
            content: "Second content body",
            isPremium: false
        )

        XCTAssertEqual(first.fortuneScore, second.fortuneScore)
        XCTAssertEqual(first.luckyNumbers, second.luckyNumbers)
        XCTAssertEqual(first.powerColors, second.powerColors)
    }

    func testDailyReadingUsesProvidedDateForDeterministicSeed() {
        let birthdate = Date(timeIntervalSince1970: 915_148_800) // 1999-01-01
        let user = UserProfile(name: "Date Anchored User", birthdate: birthdate, mbtiType: .INFJ)
        user.id = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard
            let march5Noon = formatter.date(from: "2026-03-05 12:00"),
            let march6Noon = formatter.date(from: "2026-03-06 12:00")
        else {
            XCTFail("Failed to construct deterministic test dates")
            return
        }

        let first = DailyReading(
            user: user,
            category: .social,
            content: "Same day one",
            isPremium: false,
            date: march5Noon
        )
        let second = DailyReading(
            user: user,
            category: .social,
            content: "Same day two",
            isPremium: false,
            date: march5Noon
        )
        let nextDay = DailyReading(
            user: user,
            category: .social,
            content: "Next day",
            isPremium: false,
            date: march6Noon
        )

        XCTAssertEqual(first.fortuneScore, second.fortuneScore)
        XCTAssertEqual(first.luckyNumbers, second.luckyNumbers)
        XCTAssertEqual(first.powerColors, second.powerColors)

        let identicalAcrossDays =
            first.fortuneScore == nextDay.fortuneScore
            && first.luckyNumbers == nextDay.luckyNumbers
            && first.powerColors == nextDay.powerColors
        XCTAssertFalse(identicalAcrossDays)
    }

    func testDailyReadingContentWordLimitsAreEnforced() {
        let birthdate = Date(timeIntervalSince1970: 915_148_800) // 1999-01-01
        let user = UserProfile(name: "Word Limit User", birthdate: birthdate, mbtiType: .ENTP)
        let longContent = (1...500).map { "word\($0)" }.joined(separator: " ")

        let freeReading = DailyReading(
            user: user,
            category: .health,
            content: longContent,
            isPremium: false
        )
        let premiumReading = DailyReading(
            user: user,
            category: .health,
            content: longContent,
            isPremium: true
        )

        XCTAssertEqual(freeReading.content.split(whereSeparator: \.isWhitespace).count, 150)
        XCTAssertEqual(premiumReading.content.split(whereSeparator: \.isWhitespace).count, 350)
    }

    func testDailyReadingContentCharacterLimitIsEnforcedForSingleToken() {
        let birthdate = Date(timeIntervalSince1970: 915_148_800) // 1999-01-01
        let user = UserProfile(name: "Character Limit User", birthdate: birthdate, mbtiType: .INTJ)
        let oversizedToken = String(repeating: "x", count: 6_000)

        let reading = DailyReading(
            user: user,
            category: .career,
            content: oversizedToken,
            isPremium: true
        )

        XCTAssertEqual(reading.content.count, 5_000)
    }

    func testDailyReadingContentCharacterLimitTrimsAtWordBoundary() {
        let birthdate = Date(timeIntervalSince1970: 915_148_800) // 1999-01-01
        let user = UserProfile(name: "Word Boundary User", birthdate: birthdate, mbtiType: .INFJ)
        let fixedWord = String(repeating: "a", count: 16)
        let oversizedContent = Array(repeating: fixedWord, count: 300).joined(separator: " ")

        let reading = DailyReading(
            user: user,
            category: .social,
            content: oversizedContent,
            isPremium: true
        )

        let words = reading.content.split(whereSeparator: \.isWhitespace)
        XCTAssertLessThanOrEqual(reading.content.count, 5_000)
        XCTAssertLessThan(words.count, 300)
        XCTAssertTrue(words.allSatisfy { $0.count == fixedWord.count })
        XCTAssertFalse(reading.content.last?.isWhitespace ?? false)
    }

    func testDailyReadingDeterministicExtrasMatchCanonicalEdgeSeedForAlphabeticUUIDs() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard
            let birthdate = formatter.date(from: "1999-04-01 12:00"),
            let readingDate = formatter.date(from: "2026-03-05 12:00")
        else {
            XCTFail("Failed to construct deterministic test dates")
            return
        }

        let user = UserProfile(name: "Alphabetic UUID User", birthdate: birthdate, mbtiType: .INTJ)
        user.id = UUID(uuidString: "7e7e2f55-3f2a-4b2e-a93f-3af6be27d241")!

        let reading = DailyReading(
            user: user,
            category: .career,
            content: "Canonical seed check",
            isPremium: false,
            date: readingDate
        )

        XCTAssertEqual(reading.fortuneScore, 87)
        XCTAssertEqual(reading.luckyNumbers, [21, 44, 63, 93, 94])
        XCTAssertEqual(reading.powerColors, ["Emerald", "Teal", "Gold"])
    }
}
