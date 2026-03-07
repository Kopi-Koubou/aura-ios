import SwiftData
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@Model
final class DailyReading {
    @Attribute(.unique) var id: UUID
    var date: Date
    var category: SituationCategory
    var content: String
    var fortuneScore: Int
    var luckyNumbers: [Int]
    var powerColors: [String]
    var isPremium: Bool
    var createdAt: Date

    var user: UserProfile?

    init(
        user: UserProfile,
        category: SituationCategory,
        content: String,
        isPremium: Bool = false,
        date: Date = Date()
    ) {
        let createdAt = Date()
        self.id = UUID()
        self.date = date
        self.category = category
        self.isPremium = isPremium
        self.content = Self.validatedContent(content, isPremium: isPremium)
        self.createdAt = createdAt
        self.user = user

        // Stable, locale-independent daily seed (same user + same day key -> same values).
        let seed = Self.dailySeed(for: user, date: date)
        var seededRandom = SeededRandomGenerator(seed: seed)
        self.fortuneScore = seededRandom.randomInt(in: 60...95)
        self.luckyNumbers = seededRandom.randomUniqueInts(count: 5, in: 1...99).sorted()
        self.powerColors = seededRandom.randomPowerColors()
    }

    private static let freeContentWordLimit = 150
    private static let premiumContentWordLimit = 350
    private static let dailyReadingCharacterLimit = 5000

    private static let seedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dailySeed(for user: UserProfile, date: Date) -> String {
        let dayKey = seedDateFormatter.string(from: date)
        return "\(user.id.uuidString)|\(user.zodiacSign.rawValue)|\(dayKey)"
    }

    private static func validatedContent(_ content: String, isPremium: Bool) -> String {
        let normalized = content
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum."
        let candidate = normalized.isEmpty ? fallback : normalized
        let wordLimit = isPremium ? premiumContentWordLimit : freeContentWordLimit
        let words = candidate.split(whereSeparator: \.isWhitespace)
        let wordBoundedContent: String

        if words.count > wordLimit {
            wordBoundedContent = words.prefix(wordLimit).joined(separator: " ")
        } else {
            wordBoundedContent = candidate
        }

        return truncateByCharacterLimit(wordBoundedContent, limit: dailyReadingCharacterLimit)
    }

    // MARK: - Daily Mantra (computed, no migration needed)

    func dailyMantra(fallback: String = "Trust the process.") -> String {
        guard let user else { return fallback }
        let seed = Self.dailySeed(for: user, date: date) + "|mantra"
        var generator = SeededRandomGenerator(seed: seed)
        return Self.mantraPool[generator.randomInt(in: 0...(Self.mantraPool.count - 1))]
    }

    private static let mantraPool: [String] = [
        "Small, steady steps outpace bursts of speed.",
        "What you nurture today shapes what arrives tomorrow.",
        "Clarity follows when you stop forcing answers.",
        "Your energy is a finite gift — spend it with intention.",
        "One honest conversation can shift everything.",
        "Stillness is not stalling; it's gathering strength.",
        "Let go of the version of today you planned. Welcome the one unfolding.",
        "Progress hides in the details others overlook.",
        "Not every opportunity deserves a yes.",
        "The most powerful thing you can do right now is decide.",
        "Protect your peace the way you protect your time.",
        "Something you've been avoiding holds the key you need.",
        "Kindness toward yourself isn't soft — it's strategic.",
        "You are allowed to outgrow what once fit perfectly.",
        "Focus on depth today, not breadth.",
        "The answer you're looking for lives in your body, not your mind.",
        "What feels slow is still movement.",
        "Give your ideas room to breathe before you judge them.",
        "A boundary set today prevents a crisis next week.",
        "Your instincts have earned your trust.",
        "Release the need to be understood by everyone.",
        "The right pace is your pace.",
        "Show up before you feel ready.",
        "Rest is not a reward — it's a requirement.",
    ]

    private static func truncateByCharacterLimit(_ content: String, limit: Int) -> String {
        guard content.count > limit else {
            return content
        }

        let limitIndex = content.index(content.startIndex, offsetBy: limit)
        let truncated = String(content[..<limitIndex])

        if let whitespaceRange = truncated.range(
            of: "\\s",
            options: [.regularExpression, .backwards]
        ) {
            let bounded = truncated[..<whitespaceRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !bounded.isEmpty {
                return bounded
            }
        }

        return truncated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Seeded Random Generator
struct SeededRandomGenerator {
    private var state: UInt32
    private static let lcgMultiplier: UInt32 = 1_664_525
    private static let lcgIncrement: UInt32 = 1_013_904_223

    init(seed: String) {
        // Keep this aligned with the edge function deterministic extras generator.
        self.state = Self.fnv1a32(seed)
    }

    mutating func randomInt(in range: ClosedRange<Int>) -> Int {
        state = Self.lcgMultiplier &* state &+ Self.lcgIncrement
        let span = UInt32(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(state % span)
    }

    mutating func randomUniqueInts(count: Int, in range: ClosedRange<Int>) -> [Int] {
        let uniqueLimit = range.upperBound - range.lowerBound + 1
        let targetCount = min(count, uniqueLimit)
        var result = Set<Int>()
        result.reserveCapacity(targetCount)

        while result.count < targetCount {
            result.insert(randomInt(in: range))
        }

        return Array(result)
    }

    mutating func randomPowerColors() -> [String] {
        var remainingColors = ["Purple", "Gold", "Teal", "Crimson", "Sapphire", "Emerald", "Amber", "Silver"]
        var selected: [String] = []
        selected.reserveCapacity(3)

        while selected.count < 3 && !remainingColors.isEmpty {
            let index = randomInt(in: 0...(remainingColors.count - 1))
            selected.append(remainingColors.remove(at: index))
        }

        return selected
    }

    private static func fnv1a32(_ input: String) -> UInt32 {
        let offsetBasis: UInt32 = 0x811C9DC5
        let prime: UInt32 = 0x01000193
        var hash = offsetBasis

        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash &*= prime
        }

        return hash
    }
}
