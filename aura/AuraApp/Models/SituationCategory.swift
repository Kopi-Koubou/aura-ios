import Foundation

enum SituationCategory: String, Codable, CaseIterable {
    case career = "Career"
    case love = "Love"
    case social = "Social"
    case health = "Health"
    case personalGrowth = "Personal Growth"
    
    var icon: String {
        switch self {
        case .career: return "briefcase"
        case .love: return "heart"
        case .social: return "person.3"
        case .health: return "heart.fill"
        case .personalGrowth: return "sparkles"
        }
    }
}
