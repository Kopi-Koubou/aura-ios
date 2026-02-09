import SwiftData
import Foundation

@available(iOS 17.0, macOS 14.0, *)
@Model
final class MBTIResult {
    @Attribute(.unique) var id: UUID
    var typeCode: String
    var dimensionScores: [DimensionScore]
    var cognitiveFunctions: [CognitiveFunction]
    var strengths: [String]
    var weaknesses: [String]
    var takenAt: Date
    
    var user: UserProfile?
    
    init(typeCode: String, dimensionScores: [DimensionScore]) {
        self.id = UUID()
        self.typeCode = typeCode
        self.dimensionScores = dimensionScores
        self.cognitiveFunctions = MBTIType.cognitiveFunctions(for: typeCode)
        self.strengths = MBTIType.strengths(for: typeCode)
        self.weaknesses = MBTIType.weaknesses(for: typeCode)
        self.takenAt = Date()
    }
}
