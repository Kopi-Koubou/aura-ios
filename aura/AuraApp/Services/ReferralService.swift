import Foundation
import SwiftData

enum ReferralError: Error {
    case invalidCode
    case alreadyRedeemed
    case selfReferral
    case expired
    case networkError
    case serverError(String)
    case noAuthToken
    case decodingError

    var userFriendlyMessage: String {
        switch self {
        case .invalidCode:
            return "This referral code doesn't exist. Please check and try again."
        case .alreadyRedeemed:
            return "You've already redeemed a referral code."
        case .selfReferral:
            return "You can't use your own referral code."
        case .expired:
            return "This referral code has expired."
        case .networkError:
            return "Unable to connect. Please check your internet and try again."
        case .serverError(let message):
            return message.isEmpty ? "Something went wrong. Please try again later." : message
        case .noAuthToken:
            return "Please sign in to redeem a referral code."
        case .decodingError:
            return "Something went wrong. Please try again later."
        }
    }
}

struct ReferralRedemptionResponse: Codable {
    let success: Bool
    let message: String
    let premiumGranted: Bool?
    let premiumDays: Int?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case premiumGranted = "premium_granted"
        case premiumDays = "premium_days"
    }
}

struct ReferralRedemptionRequest: Codable {
    let referralCode: String

    enum CodingKeys: String, CodingKey {
        case referralCode = "referral_code"
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class ReferralService {
    static let shared = ReferralService()

    private let codeLength = 8
    private let alphanumericCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    private var modelContext: ModelContext?

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Code Generation

    func generateReferralCode() -> String {
        String((0..<codeLength).map { _ in
            alphanumericCharacters.randomElement()!
        })
    }

    func isValidCodeFormat(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == codeLength else { return false }
        return trimmed.allSatisfy { alphanumericCharacters.contains($0) }
    }

    // MARK: - Code Redemption

    func redeemCode(_ code: String, authToken: String) async throws -> ReferralRedemptionResponse {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard isValidCodeFormat(trimmedCode) else {
            throw ReferralError.invalidCode
        }

        guard !authToken.isEmpty else {
            throw ReferralError.noAuthToken
        }

        let baseURL = Secrets.supabaseURL
        guard let url = URL(string: "\(baseURL)/functions/v1/referral-redeem") else {
            throw ReferralError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let requestBody = ReferralRedemptionRequest(referralCode: trimmedCode)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReferralError.networkError
        }

        let decoded: ReferralRedemptionResponse
        do {
            decoded = try JSONDecoder().decode(ReferralRedemptionResponse.self, from: data)
        } catch {
            throw ReferralError.decodingError
        }

        guard httpResponse.statusCode == 200, decoded.success else {
            throw mapErrorFromMessage(decoded.message)
        }

        if decoded.premiumGranted == true, let days = decoded.premiumDays {
            try await updateLocalPremiumStatus(days: days)
        }

        return decoded
    }

    // MARK: - Local Storage

    private func updateLocalPremiumStatus(days: Int) async throws {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<UserProfile>()
        guard let user = try context.fetch(descriptor).first else { return }

        let newExpiryDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()

        if let existing = user.premiumExpiresAt, existing > Date() {
            user.premiumExpiresAt = Calendar.current.date(byAdding: .day, value: days, to: existing)
        } else {
            user.premiumExpiresAt = newExpiryDate
        }

        user.updatedAt = Date()
        try context.save()
    }

    func hasRedeemedCode(userId: UUID) -> Bool {
        guard let context = modelContext else { return false }

        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == userId })
        guard let user = try? context.fetch(descriptor).first else { return false }

        return user.referredBy != nil
    }

    func getUserReferralCode(userId: UUID) -> String? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == userId })
        guard let user = try? context.fetch(descriptor).first else { return nil }

        return user.referralCode
    }

    func setUserReferralCode(_ code: String, userId: UUID) throws {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == userId })
        guard let user = try context.fetch(descriptor).first else { return }

        user.referralCode = code
        user.updatedAt = Date()
        try context.save()
    }

    // MARK: - Error Mapping

    private func mapErrorFromMessage(_ message: String) -> ReferralError {
        let lowercased = message.lowercased()

        if lowercased.contains("already") || lowercased.contains("redeemed") {
            return .alreadyRedeemed
        } else if lowercased.contains("self") || lowercased.contains("own") {
            return .selfReferral
        } else if lowercased.contains("expired") {
            return .expired
        } else if lowercased.contains("invalid") || lowercased.contains("not found") {
            return .invalidCode
        }

        return .serverError(message)
    }
}
