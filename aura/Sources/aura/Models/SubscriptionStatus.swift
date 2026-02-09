import SwiftData
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@Model
final class SubscriptionStatus {
    @Attribute(.unique) var id: UUID
    var tier: SubscriptionTier
    var expiresAt: Date?
    var isActive: Bool
    var updatedAt: Date
    
    var canAccessPremiumContent: Bool {
        tier == .premium && isActive
    }
    
    var canViewHistoricalData: Bool {
        tier == .premium && isActive
    }
    
    init(tier: SubscriptionTier = .free) {
        self.id = UUID()
        self.tier = tier
        self.isActive = tier == .free
        self.updatedAt = Date()
    }
}
