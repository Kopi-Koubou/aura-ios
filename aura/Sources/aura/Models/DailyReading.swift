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
    
    init(user: UserProfile, category: SituationCategory, content: String, isPremium: Bool = false) {
        self.id = UUID()
        self.date = Date()
        self.category = category
        self.content = content
        self.isPremium = isPremium
        self.createdAt = Date()
        self.user = user
        
        // CRIT-002 FIX: Deterministic fortune scores based on user ID + date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())
        
        var seededRandom = SeededRandomGenerator(seed: user.id.uuidString + dateString)
        self.fortuneScore = seededRandom.randomInt(in: 60...95)
        self.luckyNumbers = seededRandom.randomUniqueInts(count: 5, in: 1...99).sorted()
        self.powerColors = seededRandom.randomPowerColors()
    }
}

// MARK: - Seeded Random Generator
struct SeededRandomGenerator {
    private var state: UInt64
    
    init(seed: String) {
        // Create deterministic seed from string
        var hash = seed.hashValue
        if hash < 0 { hash = -hash }
        self.state = UInt64(hash)
    }
    
    mutating func randomInt(in range: ClosedRange<Int>) -> Int {
        // Linear congruential generator for deterministic randomness
        state = 6364136223846793005 &* state &+ 1
        let randomValue = Int(state % UInt64(range.upperBound - range.lowerBound + 1))
        return range.lowerBound + randomValue
    }
    
    mutating func randomUniqueInts(count: Int, in range: ClosedRange<Int>) -> [Int] {
        var result: [Int] = []
        var attempts = 0
        let maxAttempts = range.upperBound - range.lowerBound + 1
        
        while result.count < count && attempts < maxAttempts {
            let value = randomInt(in: range)
            if !result.contains(value) {
                result.append(value)
            }
            attempts += 1
        }
        
        // If we couldn't get enough unique numbers, fill with sequential
        while result.count < count {
            let nextValue = range.lowerBound + result.count
            if !result.contains(nextValue) {
                result.append(nextValue)
            }
        }
        
        return result
    }
    
    mutating func randomPowerColors() -> [String] {
        let allColors = ["Purple", "Gold", "Teal", "Crimson", "Sapphire", "Emerald", "Amber", "Silver"]
        var selected: [String] = []
        
        while selected.count < 3 {
            let index = randomInt(in: 0...(allColors.count - 1))
            let color = allColors[index]
            if !selected.contains(color) {
                selected.append(color)
            }
        }
        
        return selected
    }
}
