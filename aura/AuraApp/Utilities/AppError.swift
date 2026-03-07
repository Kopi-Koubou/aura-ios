import Foundation

enum AppError: Error, LocalizedError {
    case failedToLoadUser
    case failedToCreateUser
    case failedToLoadReading
    case failedToGenerateReading
    case authFailed
    case syncFailed
    case syncDeferred
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
        case .failedToCreateUser:
            return "Failed to create your profile"
        case .failedToLoadReading:
            return "Failed to load daily reading"
        case .failedToGenerateReading:
            return "Failed to generate new reading"
        case .authFailed:
            return "Authentication failed"
        case .syncFailed:
            return "Failed to sync data"
        case .syncDeferred:
            return "Saved locally. Cloud sync will retry automatically."
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

    var alertTitle: String {
        switch self {
        case .authFailed:
            return "Sign In Required"
        case .networkError:
            return "Network Issue"
        case .contentNotAvailable:
            return "Content Unavailable"
        default:
            return "Something Went Wrong"
        }
    }

    static func fromReadingLoadError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .apiError(let statusCode, _):
                switch statusCode {
                case 401, 403:
                    return .authFailed
                case 429:
                    return .contentNotAvailable
                case 400, 409, 422:
                    return .failedToGenerateReading
                default:
                    return .failedToLoadReading
                }
            case .missingAPIKey, .rateLimitExceeded:
                return .contentNotAvailable
            case .invalidResponse:
                return .networkError
            }
        }

        if error is URLError {
            return .networkError
        }

        return .failedToLoadReading
    }
}
