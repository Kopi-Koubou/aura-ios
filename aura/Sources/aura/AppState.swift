import SwiftUI
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
@Observable
final class AppState {
    var currentUser: UserProfile?
    var subscriptionStatus: SubscriptionStatus
    var isLoading = false
    var error: AppError?
    var contentService: ContentService?

    init() {
        self.subscriptionStatus = SubscriptionStatus()
    }

    func setup(modelContext: ModelContext) {
        let openAI = OpenAIService(apiKey: Secrets.openAIKey)
        self.contentService = ContentService(
            modelContext: modelContext,
            openAIService: openAI,
            subscriptionManager: SubscriptionManager.shared
        )
    }

    func loadUser(modelContext: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<UserProfile>()
        if let user = try? modelContext.fetch(descriptor).first {
            currentUser = user
            await SubscriptionManager.shared.identify(userId: user.id.uuidString)
        }
    }

    func refreshSubscription() async {
        await SubscriptionManager.shared.refreshStatus()
        subscriptionStatus.tier = SubscriptionManager.shared.isPremium ? .premium : .free
        subscriptionStatus.isActive = SubscriptionManager.shared.isPremium
    }
}
