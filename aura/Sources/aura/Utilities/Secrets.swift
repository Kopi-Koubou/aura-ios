import Foundation

enum Secrets {
    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }
    
    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }
    
    static var revenueCatAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
    }
    
    static var openAIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    }
}
