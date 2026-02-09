import Foundation
import SwiftData

enum AuthError: Error {
    case signUpFailed
    case signInFailed
    case userNotFound
    case syncFailed
}

@available(iOS 17.0, macOS 14.0, *)
final class AuthService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func signUp(email: String, password: String, name: String, birthdate: Date, mbtiType: MBTIType) async throws -> UserProfile {
        // Create local profile
        let profile = UserProfile(name: name, birthdate: birthdate, mbtiType: mbtiType)
        modelContext.insert(profile)
        try modelContext.save()
        return profile
    }
    
    func signIn(email: String, password: String) async throws -> UserProfile {
        throw AuthError.userNotFound
    }
    
    func fetchLocalUser(id: UUID) throws -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }
}
