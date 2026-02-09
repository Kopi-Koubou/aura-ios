import Foundation
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
final class ReadingRepository {
    private let modelContext: ModelContext
    private let openAIService: OpenAIService
    
    init(modelContext: ModelContext, openAIService: OpenAIService) {
        self.modelContext = modelContext
        self.openAIService = openAIService
    }
    
    func fetchLocal(user: UserProfile, category: SituationCategory, date: Date) async throws -> DailyReading? {
        let calendar = Calendar.current
        // Simplified predicate without optional chaining
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.category == category
        })
        let readings = try modelContext.fetch(descriptor)
        // Filter in memory for user and date match
        return readings.first { 
            $0.user?.id == user.id && calendar.isDate($0.date, inSameDayAs: date) 
        }
    }
    
    func generate(user: UserProfile, category: SituationCategory, isPremium: Bool = false) async throws -> DailyReading {
        let content = try await openAIService.generateHoroscope(
            zodiacSign: user.zodiacSign,
            mbtiType: user.mbtiType,
            category: category,
            isPremium: isPremium
        )
        
        let reading = DailyReading(user: user, category: category, content: content, isPremium: isPremium)
        modelContext.insert(reading)
        try modelContext.save()
        
        return reading
    }
}
