import Foundation

@available(iOS 17.0, macOS 14.0, *)
final class OpenAIService {
    private let apiKey: String
    private let supabaseURL: String
    private let supabaseAnonKey: String
    private let session: URLSession
    private let authTokenProvider: @Sendable () async -> String?
    private let cache: NSCache<NSString, NSString>

    // Rate limiting properties - using actor for thread safety
    private let rateLimiter = RateLimiter()

    private static let freeContentWordLimit = 150
    private static let premiumContentWordLimit = 350
    private static let dailyReadingCharacterLimit = 5000

    init(
        apiKey: String,
        supabaseURL: String = Secrets.supabaseURL,
        supabaseAnonKey: String = Secrets.supabaseAnonKey,
        session: URLSession = .shared,
        authTokenProvider: @escaping @Sendable () async -> String? = {
            let token = Secrets.supabaseAccessToken
            return token.isEmpty ? nil : token
        }
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supabaseURL = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supabaseAnonKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.authTokenProvider = authTokenProvider
        self.cache = NSCache()
        self.cache.countLimit = 100
    }

    func generateHoroscope(
        userID: UUID,
        zodiacSign: ZodiacSign,
        mbtiType: MBTIType,
        category: SituationCategory,
        isPremium: Bool,
        date: Date = Date()
    ) async throws -> String {
        let dateString = Self.cacheDateFormatter.string(from: date)
        let accessTier = isPremium ? "premium" : "free"
        let cacheKey = "\(userID.uuidString)_\(zodiacSign.rawValue)_\(mbtiType.rawValue)_\(category.rawValue)_\(accessTier)_\(dateString)" as NSString

        // Check in-memory cache for identical same-day requests.
        if let cached = cache.object(forKey: cacheKey) {
            return cached as String
        }

        let prompt = buildPrompt(
            zodiacSign: zodiacSign,
            mbtiType: mbtiType,
            category: category,
            isPremium: isPremium
        )
        let edgeConfigured = isEdgeFunctionConfigured()

        let response: String
        do {
            if edgeConfigured {
                if let edgeResponse = try await fetchFromEdgeFunction(
                    userID: userID,
                    zodiacSign: zodiacSign,
                    mbtiType: mbtiType,
                    category: category,
                    isPremium: isPremium,
                    dateString: dateString
                ) {
                    response = edgeResponse
                } else {
                    // Edge accepted the request but returned no content payload.
                    response = fallbackResponse(
                        zodiacSign: zodiacSign,
                        mbtiType: mbtiType,
                        category: category
                    )
                }
            } else {
                response = await fetchDirectOrFallback(
                    prompt: prompt,
                    maxTokens: isPremium ? 500 : 200,
                    zodiacSign: zodiacSign,
                    mbtiType: mbtiType,
                    category: category
                )
            }
        } catch {
            if shouldFallbackToLocalTemplate(after: error) {
                // Keep responses available without bypassing edge guardrails.
                response = fallbackResponse(
                    zodiacSign: zodiacSign,
                    mbtiType: mbtiType,
                    category: category
                )
            } else {
                throw error
            }
        }

        let sanitized = sanitizeContent(response, isPremium: isPremium)
        cache.setObject(sanitized as NSString, forKey: cacheKey)
        return sanitized
    }

    private func fetchFromOpenAI(prompt: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: "gpt-4o-mini",
            messages: [
                .init(
                    role: "system",
                    content: "You are an empathetic astrologer for the Aura app. Keep responses grounded, specific, and actionable."
                ),
                .init(role: "user", content: prompt)
            ],
            temperature: 0.8,
            maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.invalidResponse
        }

        return content
    }

    private func fetchFromEdgeFunction(
        userID: UUID,
        zodiacSign: ZodiacSign,
        mbtiType: MBTIType,
        category: SituationCategory,
        isPremium: Bool,
        dateString: String
    ) async throws -> String? {
        guard let edgeURL = edgeFunctionURL(), !supabaseAnonKey.isEmpty else {
            return nil
        }

        var request = URLRequest(url: edgeURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let authToken = await resolveAuthToken()
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let body = EdgeGenerationRequest(
            userID: userID.uuidString,
            zodiacSign: zodiacSign.rawValue,
            mbtiType: mbtiType.rawValue,
            category: category.rawValue,
            isPremium: isPremium,
            date: dateString
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        logEdgeAuthMetadata(from: httpResponse, hadAuthToken: authToken != nil)

        guard (200...299).contains(httpResponse.statusCode) else {
            let decodedError = try? JSONDecoder().decode(EdgeGenerationResponse.self, from: data)
            let fallbackMessage = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: decodedError?.error ?? fallbackMessage
            )
        }

        let decoded = try JSONDecoder().decode(EdgeGenerationResponse.self, from: data)
        guard let content = decoded.reading?.content else {
            return nil
        }

        return content
    }

    private func fetchDirectOrFallback(
        prompt: String,
        maxTokens: Int,
        zodiacSign: ZodiacSign,
        mbtiType: MBTIType,
        category: SituationCategory
    ) async -> String {
        do {
            try await rateLimiter.checkRateLimit()

            guard !apiKey.isEmpty else {
                throw OpenAIError.missingAPIKey
            }

            return try await fetchFromOpenAI(prompt: prompt, maxTokens: maxTokens)
        } catch {
            // Fallback keeps the app usable if network/API/auth is unavailable.
            return fallbackResponse(
                zodiacSign: zodiacSign,
                mbtiType: mbtiType,
                category: category
            )
        }
    }

    private func edgeFunctionURL() -> URL? {
        guard !supabaseURL.isEmpty else { return nil }

        let trimmedBase: String
        if supabaseURL.hasSuffix("/") {
            trimmedBase = String(supabaseURL.dropLast())
        } else {
            trimmedBase = supabaseURL
        }

        return URL(string: "\(trimmedBase)/functions/v1/generate-horoscope")
    }

    private func isEdgeFunctionConfigured() -> Bool {
        edgeFunctionURL() != nil && !supabaseAnonKey.isEmpty
    }

    private func resolveAuthToken() async -> String? {
        let token = await authTokenProvider()
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private func shouldFallbackToLocalTemplate(after error: Error) -> Bool {
        guard let openAIError = error as? OpenAIError else {
            return true
        }

        switch openAIError {
        case .apiError(let statusCode, _):
            // Preserve server-side auth/rate-limit policy for known client/policy violations.
            let nonFallbackStatusCodes: Set<Int> = [400, 401, 403, 409, 422, 429]
            if nonFallbackStatusCodes.contains(statusCode) {
                print("OpenAIService edge client error status=\(statusCode); local template fallback disabled.")
                return false
            }
            return true
        case .missingAPIKey, .invalidResponse, .rateLimitExceeded:
            return true
        }
    }

    private func logEdgeAuthMetadata(from response: HTTPURLResponse, hadAuthToken: Bool) {
        let authModeHeader = response.value(forHTTPHeaderField: "x-aura-auth-mode")
        let resolvedAuthMode = Secrets.applyGenerateHoroscopeAuthModeFromServerHeader(authModeHeader)
        let authMode = resolvedAuthMode?.rawValue ?? authModeHeader?.lowercased() ?? "unknown"
        let authContext = response.value(forHTTPHeaderField: "x-aura-auth-context")?.lowercased() ?? "unknown"
        let usedFallback = response.value(forHTTPHeaderField: "x-aura-auth-fallback") == "1"

        guard usedFallback || (hadAuthToken && authContext == "invalid") else {
            return
        }

        print(
            "OpenAIService edge auth metadata mode=\(authMode) context=\(authContext) fallback=\(usedFallback ? "1" : "0")"
        )
    }

    private func buildPrompt(zodiacSign: ZodiacSign, mbtiType: MBTIType, category: SituationCategory, isPremium: Bool) -> String {
        let wordCount = isPremium ? "250-350" : "100-150"
        return """
        Generate a daily horoscope reading for a \(mbtiType.rawValue) \(zodiacSign.rawValue) focused on \(category.rawValue).

        Tone: Positive, empowering, actionable.
        Length: \(wordCount) words.
        Include:
        - A concrete observation for today
        - A practical next step
        - A short encouraging close

        Keep it personalized to both MBTI cognitive preferences and zodiac tendencies.
        """
    }

    private func fallbackResponse(zodiacSign: ZodiacSign, mbtiType: MBTIType, category: SituationCategory) -> String {
        "Today favors your \(category.rawValue) focus. As a \(mbtiType.rawValue) \(zodiacSign.rawValue), trust your pattern-recognition and take one concrete step before the day ends. Small momentum now will compound quickly."
    }

    private func sanitizeContent(_ content: String, isPremium: Bool) -> String {
        let normalized = content
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum."
        let candidate = normalized.isEmpty ? fallback : normalized
        let wordLimit = isPremium ? Self.premiumContentWordLimit : Self.freeContentWordLimit
        let words = candidate.split(whereSeparator: \.isWhitespace)
        let wordBoundedContent: String

        if words.count > wordLimit {
            wordBoundedContent = words.prefix(wordLimit).joined(separator: " ")
        } else {
            wordBoundedContent = candidate
        }

        return truncateByCharacterLimit(wordBoundedContent, limit: Self.dailyReadingCharacterLimit)
    }

    private func truncateByCharacterLimit(_ content: String, limit: Int) -> String {
        guard content.count > limit else {
            return content
        }

        let limitIndex = content.index(content.startIndex, offsetBy: limit)
        let truncated = String(content[..<limitIndex])

        if let whitespaceRange = truncated.range(
            of: "\\s",
            options: [.regularExpression, .backwards]
        ) {
            let bounded = truncated[..<whitespaceRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !bounded.isEmpty {
                return bounded
            }
        }

        return truncated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let cacheDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct EdgeGenerationRequest: Encodable {
    let userID: String
    let zodiacSign: String
    let mbtiType: String
    let category: String
    let isPremium: Bool
    let date: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case zodiacSign = "zodiac_sign"
        case mbtiType = "mbti_type"
        case category
        case isPremium = "is_premium"
        case date
    }
}

private struct EdgeGenerationResponse: Decodable {
    let reading: EdgeGeneratedReading?
    let error: String?
}

private struct EdgeGeneratedReading: Decodable {
    let content: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct OpenAIAPIErrorResponse: Decodable {
    let error: OpenAIAPIErrorBody
}

private struct OpenAIAPIErrorBody: Decodable {
    let message: String
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
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case rateLimitExceeded(waitTime: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is missing."
        case .invalidResponse:
            return "Received an invalid response from OpenAI."
        case .apiError(let statusCode, let message):
            return "OpenAI API error (\(statusCode)): \(message)"
        case .rateLimitExceeded(let waitTime):
            return "Rate limit exceeded. Please wait \(Int(ceil(waitTime))) seconds before trying again."
        }
    }
}
