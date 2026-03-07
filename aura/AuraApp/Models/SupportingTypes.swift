import Foundation
import SwiftData

struct DimensionScore: Codable {
    let dimension: String
    let score: Double
}

struct CognitiveFunction: Codable {
    let name: String
    let position: Int
}

@available(iOS 17.0, macOS 14.0, *)
enum PendingSyncOperationType: String, Codable {
    case userProfile
    case dailyReading
}

@available(iOS 17.0, macOS 14.0, *)
@Model
final class PendingSyncOperation {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var dedupeKey: String
    var payload: Data
    var attempts: Int
    var nextRetryAt: Date
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        type: PendingSyncOperationType,
        dedupeKey: String,
        payload: Data,
        attempts: Int = 0,
        nextRetryAt: Date = Date(),
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = UUID()
        self.typeRawValue = type.rawValue
        self.dedupeKey = dedupeKey
        self.payload = payload
        self.attempts = attempts
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: PendingSyncOperationType {
        get { PendingSyncOperationType(rawValue: typeRawValue) ?? .dailyReading }
        set { typeRawValue = newValue.rawValue }
    }
}
