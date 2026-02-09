import Foundation

enum MBTIType: String, Codable, CaseIterable {
    case INTJ, INTP, ENTJ, ENTP
    case INFJ, INFP, ENFJ, ENFP
    case ISTJ, ISFJ, ESTJ, ESFJ
    case ISTP, ISFP, ESTP, ESFP
    
    static func cognitiveFunctions(for typeCode: String) -> [CognitiveFunction] {
        // Simplified mapping - full implementation would map all 16 types
        return [
            CognitiveFunction(name: "Dominant", position: 1),
            CognitiveFunction(name: "Auxiliary", position: 2),
            CognitiveFunction(name: "Tertiary", position: 3),
            CognitiveFunction(name: "Inferior", position: 4)
        ]
    }
    
    static func strengths(for typeCode: String) -> [String] {
        return ["Strategic thinking", "Independent", "Determined"]
    }
    
    static func weaknesses(for typeCode: String) -> [String] {
        return ["May appear aloof", "Perfectionist tendencies"]
    }
}
