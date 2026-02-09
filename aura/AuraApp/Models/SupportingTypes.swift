import Foundation

struct DimensionScore: Codable {
    let dimension: String
    let score: Double
}

struct CognitiveFunction: Codable {
    let name: String
    let position: Int
}
