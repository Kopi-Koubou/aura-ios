import Foundation
import SwiftData
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class ContentServiceCachingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SubscriptionManager.shared.isPremium = false
    }

    override func tearDown() {
        SubscriptionManager.shared.isPremium = false
        super.tearDown()
    }

    func testPremiumUpgradeReusesSingleSameDayReadingRecord() async throws {
        let modelContext = try makeInMemoryModelContext()
        let user = UserProfile(
            name: "Cache User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )
        modelContext.insert(user)
        try modelContext.save()

        let contentService = makeContentService(modelContext: modelContext)

        SubscriptionManager.shared.isPremium = false
        let freeReading = try await contentService.todayReading(for: user, category: .career)
        XCTAssertFalse(freeReading.isPremium)

        SubscriptionManager.shared.isPremium = true
        let upgradedReading = try await contentService.todayReading(for: user, category: .career)
        XCTAssertTrue(upgradedReading.isPremium)

        let cachedPremiumReading = try await contentService.todayReading(for: user, category: .career)
        XCTAssertTrue(cachedPremiumReading.isPremium)

        let allReadings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let sameDayCareerReadings = allReadings.filter {
            $0.user?.id == user.id
                && $0.category == .career
                && Calendar.current.isDate($0.date, inSameDayAs: Date())
        }

        XCTAssertEqual(sameDayCareerReadings.count, 1)
        XCTAssertEqual(freeReading.id, upgradedReading.id)
        XCTAssertEqual(upgradedReading.id, cachedPremiumReading.id)
        XCTAssertEqual(sameDayCareerReadings.first?.id, cachedPremiumReading.id)
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: UserProfile.self,
            DailyReading.self,
            MBTIResult.self,
            PendingSyncOperation.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeContentService(modelContext: ModelContext) -> ContentService {
        let openAIService = OpenAIService(
            apiKey: "",
            supabaseURL: "",
            supabaseAnonKey: ""
        )
        let syncService = SyncService(baseURL: "", apiKey: "")
        let syncBacklog = SyncBacklogStore(modelContext: modelContext, syncService: syncService)

        return ContentService(
            modelContext: modelContext,
            openAIService: openAIService,
            subscriptionManager: SubscriptionManager.shared,
            syncService: syncService,
            syncBacklog: syncBacklog
        )
    }
}
