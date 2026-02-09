import Foundation

@available(iOS 17.0, macOS 14.0, *)
final class OpenAIService {
    private let apiKey: String
    private let cache: NSCache<NSString, NSString>
    
    // Rate limiting properties - using actor for thread safety
    private let rateLimiter = RateLimiter()
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.cache = NSCache()
        self.cache.countLimit = 100
    }
    
    func generateHoroscope(zodiacSign: ZodiacSign, mbtiType: MBTIType, category: SituationCategory, isPremium: Bool) async throws -> String {
        // Check rate limit
        try await rateLimiter.checkRateLimit()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())
        
        let cacheKey = "\(zodiacSign.rawValue)_\(mbtiType.rawValue)_\(category.rawValue)_\(dateString)" as NSString
        
        // Check cache (5 minute TTL for identical requests)
        if let cached = cache.object(forKey: cacheKey) {
            return cached as String
        }
        
        let wordCount = isPremium ? "250-350" : "100-150"
        
        let _ = """
        Generate a daily horoscope reading for a \(mbtiType.rawValue) \(zodiacSign.rawValue) focused on \(category.rawValue).

        Tone: Positive, empowering, actionable.
        Length: \(wordCount) words.
        Include: Specific advice, cosmic context, actionable next step.

        The reading should feel personalized to both their MBTI cognitive preferences and their zodiac sign's typical traits.
        """
        
        // Simulated response - real implementation would call OpenAI API
        let response = "Today brings powerful energy for your \(category.rawValue) pursuits. As a \(mbtiType.rawValue), your natural strengths in strategic thinking align with today's cosmic alignment. Trust your intuition and take decisive action toward your goals."
        
        cache.setObject(response as NSString, forKey: cacheKey)
        return response
    }
}

// MARK: - Rate Limiter Actor
@available(iOS 17.0, macOS 14.0, *)
actor RateLimiter {
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 2.0 // Max 1 request per 2 seconds
    
    func checkRateLimit() async throws {
        let now = Date()
        
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = now.timeIntervalSince(lastRequest)
            if timeSinceLastRequest < minimumRequestInterval {
                let waitTime = minimumRequestInterval - timeSinceLastRequest
                // Wait before proceeding
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        
        lastRequestTime = Date()
    }
}

// MARK: - Rate Limit Error
enum OpenAIError: LocalizedError {
    case rateLimitExceeded(waitTime: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded(let waitTime):
            return "Rate limit exceeded. Please wait \(Int(ceil(waitTime))) seconds before trying again."
        }
    }
}
