import SwiftData
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var birthdate: Date
    var mbtiType: MBTIType
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade) var readings: [DailyReading]?
    @Relationship(deleteRule: .cascade) var mbtiResults: [MBTIResult]?
    
    var zodiacSign: ZodiacSign {
        ZodiacSign.from(date: birthdate)
    }
    
    init(name: String, birthdate: Date, mbtiType: MBTIType) {
        self.id = UUID()
        self.name = name
        self.birthdate = birthdate
        self.mbtiType = mbtiType
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
