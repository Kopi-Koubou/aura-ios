import Foundation
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
final class ContentService {
    private let modelContext: ModelContext
    private let openAIService: OpenAIService
    private let subscriptionManager: SubscriptionManager

    init(modelContext: ModelContext, openAIService: OpenAIService, subscriptionManager: SubscriptionManager) {
        self.modelContext = modelContext
        self.openAIService = openAIService
        self.subscriptionManager = subscriptionManager
    }

    func todayReading(for user: UserProfile, category: SituationCategory) async throws -> DailyReading {
        let today = Date()

        // Check SwiftData cache first
        if let cached = try fetchCachedReading(user: user, category: category, date: today) {
            // If user upgraded to premium, regenerate with full content
            if subscriptionManager.isPremium && !cached.isPremium {
                return try await generateAndCache(user: user, category: category)
            }
            return cached
        }

        return try await generateAndCache(user: user, category: category)
    }

    func allCategoryReadings(for user: UserProfile) async throws -> [SituationCategory: DailyReading] {
        var results: [SituationCategory: DailyReading] = [:]
        for category in SituationCategory.allCases {
            results[category] = try await todayReading(for: user, category: category)
        }
        return results
    }

    func purgeStaleCacheEntries() throws {
        let calendar = Calendar.current
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.date < twoDaysAgo
        })
        let staleReadings = try modelContext.fetch(descriptor)
        for reading in staleReadings {
            modelContext.delete(reading)
        }
        try modelContext.save()
    }

    // MARK: - Private

    private func fetchCachedReading(user: UserProfile, category: SituationCategory, date: Date) throws -> DailyReading? {
        let calendar = Calendar.current
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.category == category
        })
        let readings = try modelContext.fetch(descriptor)
        return readings.first {
            $0.user?.id == user.id && calendar.isDate($0.date, inSameDayAs: date)
        }
    }

    private func generateAndCache(user: UserProfile, category: SituationCategory) async throws -> DailyReading {
        let isPremium = subscriptionManager.isPremium
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
