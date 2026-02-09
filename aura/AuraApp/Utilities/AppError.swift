import Foundation

enum AppError: Error, LocalizedError {
    case failedToLoadUser
    case failedToLoadReading
    case failedToGenerateReading
    case authFailed
    case syncFailed
    case networkError
    case purchaseFailed
    case noOfferingsAvailable
    case subscriptionExpired
    case contentNotAvailable
    case shareFailed

    var errorDescription: String? {
        switch self {
        case .failedToLoadUser:
            return "Failed to load user profile"
        case .failedToLoadReading:
            return "Failed to load daily reading"
        case .failedToGenerateReading:
            return "Failed to generate new reading"
        case .authFailed:
            return "Authentication failed"
        case .syncFailed:
            return "Failed to sync data"
        case .networkError:
            return "Network error occurred"
        case .purchaseFailed:
            return "Purchase could not be completed"
        case .noOfferingsAvailable:
            return "No subscription plans available"
        case .subscriptionExpired:
            return "Your subscription has expired"
        case .contentNotAvailable:
            return "Content is not available right now"
        case .shareFailed:
            return "Failed to create share card"
        }
    }
}
