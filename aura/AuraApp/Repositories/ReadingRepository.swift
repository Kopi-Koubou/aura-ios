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
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.date >= startOfDay
                && reading.date < endOfDay
        })
        let readings = try modelContext.fetch(descriptor)
        return readings.first {
            $0.category == category
                && $0.user?.id == user.id
        }
    }
    
    func generate(
        user: UserProfile,
        category: SituationCategory,
        isPremium: Bool = false,
        date: Date = Date()
    ) async throws -> DailyReading {
        let content = try await openAIService.generateHoroscope(
            userID: user.id,
            zodiacSign: user.zodiacSign,
            mbtiType: user.mbtiType,
            category: category,
            isPremium: isPremium,
            date: date
        )

        let reading = DailyReading(
            user: user,
            category: category,
            content: content,
            isPremium: isPremium,
            date: date
        )
        modelContext.insert(reading)
        try modelContext.save()

        return reading
    }
}
