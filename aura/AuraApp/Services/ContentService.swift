import Foundation
import SwiftData

private enum DailyReadingContentGuardrails {
    static let freeWordLimit = 150
    static let premiumWordLimit = 350
    static let dailyReadingCharacterLimit = 5000
    static let fallbackContent =
        "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum."

    static func sanitize(_ content: String, isPremium: Bool) -> String {
        let normalized = content
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate = normalized.isEmpty ? fallbackContent : normalized
        let wordLimit = isPremium ? premiumWordLimit : freeWordLimit
        let words = candidate.split(whereSeparator: \.isWhitespace)
        let wordBoundedContent: String

        if words.count > wordLimit {
            wordBoundedContent = words.prefix(wordLimit).joined(separator: " ")
        } else {
            wordBoundedContent = candidate
        }

        return truncateByCharacterLimit(wordBoundedContent, limit: dailyReadingCharacterLimit)
    }

    private static func truncateByCharacterLimit(_ content: String, limit: Int) -> String {
        guard content.count > limit else {
            return content
        }

        let limitIndex = content.index(content.startIndex, offsetBy: limit)
        let truncated = String(content[..<limitIndex])

        if let whitespaceRange = truncated.range(of: "\\s", options: [.regularExpression, .backwards]) {
            let bounded = truncated[..<whitespaceRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !bounded.isEmpty {
                return bounded
            }
        }

        return truncated.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(iOS 17.0, macOS 14.0, *)
final class ContentService {
    private let modelContext: ModelContext
    private let openAIService: OpenAIService
    private let subscriptionManager: SubscriptionManager
    private let syncService: SyncService
    private let syncBacklog: SyncBacklogStore

    init(
        modelContext: ModelContext,
        openAIService: OpenAIService,
        subscriptionManager: SubscriptionManager,
        syncService: SyncService = SyncService(),
        syncBacklog: SyncBacklogStore? = nil
    ) {
        self.modelContext = modelContext
        self.openAIService = openAIService
        self.subscriptionManager = subscriptionManager
        self.syncService = syncService
        self.syncBacklog = syncBacklog ?? SyncBacklogStore(modelContext: modelContext, syncService: syncService)
    }

    func todayReading(for user: UserProfile, category: SituationCategory) async throws -> DailyReading {
        Task(priority: .utility) { [syncBacklog] in
            await syncBacklog.processDueOperations(limit: 8)
        }

        let today = Date()

        // Check SwiftData cache first
        if let cached = try fetchCachedReading(user: user, category: category, date: today) {
            // If user upgraded to premium, regenerate with full content
            if subscriptionManager.isPremium && !cached.isPremium {
                return try await generateAndCache(user: user, category: category, referenceDate: today)
            }
            return cached
        }

        return try await generateAndCache(user: user, category: category, referenceDate: today)
    }

    func cachedTodayReading(
        for user: UserProfile,
        category: SituationCategory,
        date: Date = Date()
    ) throws -> DailyReading? {
        try fetchCachedReading(user: user, category: category, date: date)
    }

    func allCategoryReadings(for user: UserProfile) async throws -> [SituationCategory: DailyReading] {
        var results: [SituationCategory: DailyReading] = [:]
        for category in SituationCategory.allCases {
            results[category] = try await todayReading(for: user, category: category)
        }
        return results
    }

    func purgeStaleCacheEntries() throws {
        let calendar = Calendar.current
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.date < twoDaysAgo
        })
        let staleReadings = try modelContext.fetch(descriptor)
        for reading in staleReadings {
            modelContext.delete(reading)
        }
        try modelContext.save()
    }

    func processPendingSyncOperations(limit: Int = 20) async {
        await syncBacklog.processDueOperations(limit: limit)
    }

    // MARK: - Private

    private func fetchCachedReading(user: UserProfile, category: SituationCategory, date: Date) throws -> DailyReading? {
        let cachedReadings = try fetchCachedReadings(user: user, category: category, date: date)
        return preferredCachedReading(
            from: cachedReadings,
            preferPremium: subscriptionManager.isPremium
        )
    }

    private func fetchCachedReadings(user: UserProfile, category: SituationCategory, date: Date) throws -> [DailyReading] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.date >= startOfDay
                && reading.date < endOfDay
        })
        let readings = try modelContext.fetch(descriptor)
        return readings.filter {
            $0.category == category
                && $0.user?.id == user.id
        }
    }

    private func preferredCachedReading(from readings: [DailyReading], preferPremium: Bool) -> DailyReading? {
        guard !readings.isEmpty else {
            return nil
        }

        return readings.sorted { lhs, rhs in
            if preferPremium && lhs.isPremium != rhs.isPremium {
                return lhs.isPremium && !rhs.isPremium
            }
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }.first
    }

    private func removeDuplicateReadings(_ readings: [DailyReading], keeping retainedReading: DailyReading) {
        for reading in readings where reading.id != retainedReading.id {
            modelContext.delete(reading)
        }
    }

    private func generateAndCache(
        user: UserProfile,
        category: SituationCategory,
        referenceDate: Date
    ) async throws -> DailyReading {
        let isPremium = subscriptionManager.isPremium
        let content = try await openAIService.generateHoroscope(
            userID: user.id,
            zodiacSign: user.zodiacSign,
            mbtiType: user.mbtiType,
            category: category,
            isPremium: isPremium,
            date: referenceDate
        )

        let generatedReading = DailyReading(
            user: user,
            category: category,
            content: content,
            isPremium: isPremium,
            date: referenceDate
        )
        let cachedReadings = try fetchCachedReadings(
            user: user,
            category: category,
            date: generatedReading.date
        )

        let reading: DailyReading
        if let retainedReading = preferredCachedReading(from: cachedReadings, preferPremium: isPremium) {
            retainedReading.content = generatedReading.content
            retainedReading.fortuneScore = generatedReading.fortuneScore
            retainedReading.luckyNumbers = generatedReading.luckyNumbers
            retainedReading.powerColors = generatedReading.powerColors
            retainedReading.isPremium = retainedReading.isPremium || generatedReading.isPremium
            retainedReading.date = generatedReading.date
            retainedReading.createdAt = generatedReading.createdAt
            removeDuplicateReadings(cachedReadings, keeping: retainedReading)
            reading = retainedReading
        } else {
            reading = generatedReading
            modelContext.insert(reading)
        }
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: reading.id,
            userID: user.id,
            date: reading.date,
            categoryRawValue: category.rawValue,
            content: reading.content,
            fortuneScore: reading.fortuneScore,
            luckyNumbers: reading.luckyNumbers,
            powerColors: reading.powerColors,
            isPremium: reading.isPremium,
            createdAt: reading.createdAt
        )
        scheduleReadingSync(snapshot: snapshot, localReadingID: reading.id)

        return reading
    }

    private func scheduleReadingSync(snapshot: SyncService.DailyReadingSnapshot, localReadingID: UUID) {
        let syncBacklog = self.syncBacklog
        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let outcome = try await syncService.syncDailyReading(snapshot)
                switch outcome {
                case .pushedLocal:
                    await syncBacklog.clearDailyReading(snapshot)
                case .remoteWins(let remote):
                    await syncBacklog.clearDailyReading(snapshot)
                    await MainActor.run {
                        self.applyRemoteReading(remote, localReadingID: localReadingID)
                    }
                case .skippedConfiguration:
                    await syncBacklog.enqueueDailyReading(
                        snapshot,
                        failureReason: "Sync service not configured."
                    )
                }
            } catch {
                await syncBacklog.enqueueDailyReading(snapshot, failure: error)
            }
        }
    }

    @MainActor
    private func applyRemoteReading(_ remote: SyncService.RemoteDailyReading, localReadingID: UUID) {
        let descriptor = FetchDescriptor<DailyReading>(predicate: #Predicate { reading in
            reading.id == localReadingID
        })

        guard let localReading = try? modelContext.fetch(descriptor).first else {
            return
        }

        localReading.content = DailyReadingContentGuardrails.sanitize(
            remote.content,
            isPremium: remote.isPremium
        )
        localReading.fortuneScore = remote.fortuneScore
        localReading.luckyNumbers = remote.luckyNumbers
        localReading.powerColors = remote.powerColors
        localReading.isPremium = remote.isPremium

        if remote.date.timeIntervalSince1970 > 0 {
            localReading.date = remote.date
        }
        if remote.createdAt.timeIntervalSince1970 > 0 {
            localReading.createdAt = remote.createdAt
        }

        try? modelContext.save()
    }
}

@available(iOS 17.0, macOS 14.0, *)
actor SyncService {
    struct UserProfileSnapshot: Codable, Sendable {
        let id: UUID
        let name: String
        let birthdate: Date
        let zodiacSignRawValue: String
        let mbtiTypeRawValue: String
        let createdAt: Date
        let updatedAt: Date
    }

    struct DailyReadingSnapshot: Codable, Sendable {
        let id: UUID
        let userID: UUID
        let date: Date
        let categoryRawValue: String
        let content: String
        let fortuneScore: Int
        let luckyNumbers: [Int]
        let powerColors: [String]
        let isPremium: Bool
        let createdAt: Date
    }

    struct RemoteUserProfile: Sendable {
        let id: UUID
        let name: String
        let birthdate: Date
        let zodiacSignRawValue: String
        let mbtiTypeRawValue: String
        let updatedAt: Date
    }

    struct RemoteDailyReading: Sendable {
        let id: UUID
        let userID: UUID
        let date: Date
        let categoryRawValue: String
        let content: String
        let fortuneScore: Int
        let luckyNumbers: [Int]
        let powerColors: [String]
        let isPremium: Bool
        let createdAt: Date
    }

    enum UserProfileSyncOutcome: Sendable {
        case pushedLocal
        case remoteWins(RemoteUserProfile)
        case skippedConfiguration
    }

    enum DailyReadingSyncOutcome: Sendable {
        case pushedLocal
        case remoteWins(RemoteDailyReading)
        case skippedConfiguration
    }

    private enum SyncError: Error {
        case invalidConfiguration
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int, body: String)
        case decodingFailed
    }

    private struct UserProfileRow: Decodable {
        let id: UUID
        let name: String
        let birthdate: String
        let zodiacSign: String
        let mbtiType: String
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case birthdate
            case zodiacSign = "zodiac_sign"
            case mbtiType = "mbti_type"
            case updatedAt = "updated_at"
        }
    }

    private struct DailyReadingRow: Decodable {
        let id: UUID
        let userID: UUID
        let date: String
        let category: String
        let content: String
        let fortuneScore: Int
        let luckyNumbers: [Int]
        let powerColors: [String]
        let isPremium: Bool
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case date
            case category
            case content
            case fortuneScore = "fortune_score"
            case luckyNumbers = "lucky_numbers"
            case powerColors = "power_colors"
            case isPremium = "is_premium"
            case createdAt = "created_at"
        }
    }

    private struct UserProfileUpsertPayload: Encodable {
        let id: UUID
        let name: String
        let birthdate: String
        let zodiacSign: String
        let mbtiType: String
        let createdAt: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case birthdate
            case zodiacSign = "zodiac_sign"
            case mbtiType = "mbti_type"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    private struct DailyReadingUpsertPayload: Encodable {
        let userID: UUID
        let date: String
        let category: String
        let content: String
        let fortuneScore: Int
        let luckyNumbers: [Int]
        let powerColors: [String]
        let isPremium: Bool
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case date
            case category
            case content
            case fortuneScore = "fortune_score"
            case luckyNumbers = "lucky_numbers"
            case powerColors = "power_colors"
            case isPremium = "is_premium"
            case createdAt = "created_at"
        }
    }

    private let baseURL: URL?
    private let apiKey: String
    private let urlSession: URLSession
    private let authTokenProvider: @Sendable () async -> String?
    private let maxAttempts = 3
    private let initialBackoffNanoseconds: UInt64 = 500_000_000
    private let maxBackoffNanoseconds: UInt64 = 4_000_000_000
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(
        baseURL: String = Secrets.supabaseURL,
        apiKey: String = Secrets.supabaseAnonKey,
        urlSession: URLSession = .shared,
        authTokenProvider: @escaping @Sendable () async -> String? = {
            let token = Secrets.supabaseAccessToken
            return token.isEmpty ? nil : token
        }
    ) {
        self.baseURL = URL(string: baseURL)
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.authTokenProvider = authTokenProvider
    }

    func syncUserProfile(_ local: UserProfileSnapshot) async throws -> UserProfileSyncOutcome {
        guard isConfigured else { return .skippedConfiguration }

        let remote = try await withRetry {
            try await fetchRemoteUserProfile(id: local.id)
        }

        if let remote, remote.updatedAt > local.updatedAt {
            return .remoteWins(remote)
        }

        try await withRetry {
            try await upsertUserProfile(local)
        }
        return .pushedLocal
    }

    func syncDailyReading(_ local: DailyReadingSnapshot) async throws -> DailyReadingSyncOutcome {
        guard isConfigured else { return .skippedConfiguration }

        let remote = try await withRetry {
            try await fetchRemoteDailyReading(local)
        }

        if let remote, shouldUseRemote(remote, over: local) {
            return .remoteWins(remote)
        }

        try await withRetry {
            try await upsertDailyReading(local)
        }
        return .pushedLocal
    }

    // MARK: - Conflict Policy

    private func shouldUseRemote(_ remote: RemoteDailyReading, over local: DailyReadingSnapshot) -> Bool {
        // Policy:
        // 1) Premium content wins over free.
        // 2) Newer writes win by createdAt.
        // 3) Timestamp ties are broken deterministically by UUID string ordering so
        //    multi-device sync converges regardless of replay order.
        if remote.isPremium != local.isPremium {
            return remote.isPremium
        }
        if remote.createdAt != local.createdAt {
            return remote.createdAt > local.createdAt
        }

        let remoteID = remote.id.uuidString.lowercased()
        let localID = local.id.uuidString.lowercased()
        return remoteID >= localID
    }

    // MARK: - Fetch Remote

    private func fetchRemoteUserProfile(id: UUID) async throws -> RemoteUserProfile? {
        let request = try await makeRequest(
            path: "rest/v1/users",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,name,birthdate,zodiac_sign,mbti_type,updated_at"),
                URLQueryItem(name: "id", value: "eq.\(id.uuidString)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        let data = try await performRequest(request)
        let rows = try decode([UserProfileRow].self, from: data)
        guard let row = rows.first else { return nil }

        return RemoteUserProfile(
            id: row.id,
            name: row.name,
            birthdate: parseDay(row.birthdate),
            zodiacSignRawValue: row.zodiacSign,
            mbtiTypeRawValue: row.mbtiType,
            updatedAt: parseTimestamp(row.updatedAt)
        )
    }

    private func fetchRemoteDailyReading(_ local: DailyReadingSnapshot) async throws -> RemoteDailyReading? {
        let request = try await makeRequest(
            path: "rest/v1/daily_readings",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,date,category,content,fortune_score,lucky_numbers,power_colors,is_premium,created_at"),
                URLQueryItem(name: "user_id", value: "eq.\(local.userID.uuidString)"),
                URLQueryItem(name: "date", value: "eq.\(dayString(from: local.date))"),
                URLQueryItem(name: "category", value: "eq.\(local.categoryRawValue)"),
                URLQueryItem(name: "limit", value: "1")
            ]
        )

        let data = try await performRequest(request)
        let rows = try decode([DailyReadingRow].self, from: data)
        guard let row = rows.first else { return nil }

        return RemoteDailyReading(
            id: row.id,
            userID: row.userID,
            date: parseDay(row.date),
            categoryRawValue: row.category,
            content: row.content,
            fortuneScore: row.fortuneScore,
            luckyNumbers: row.luckyNumbers,
            powerColors: row.powerColors,
            isPremium: row.isPremium,
            createdAt: parseTimestamp(row.createdAt)
        )
    }

    // MARK: - Push Local

    private func upsertUserProfile(_ local: UserProfileSnapshot) async throws {
        let payload = UserProfileUpsertPayload(
            id: local.id,
            name: local.name,
            birthdate: dayString(from: local.birthdate),
            zodiacSign: local.zodiacSignRawValue,
            mbtiType: local.mbtiTypeRawValue,
            createdAt: timestampString(from: local.createdAt),
            updatedAt: timestampString(from: local.updatedAt)
        )

        let body = try jsonEncoder.encode([payload])
        let request = try await makeRequest(
            path: "rest/v1/users",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )

        _ = try await performRequest(request)
    }

    private func upsertDailyReading(_ local: DailyReadingSnapshot) async throws {
        let payload = DailyReadingUpsertPayload(
            userID: local.userID,
            date: dayString(from: local.date),
            category: local.categoryRawValue,
            content: local.content,
            fortuneScore: local.fortuneScore,
            luckyNumbers: local.luckyNumbers,
            powerColors: local.powerColors,
            isPremium: local.isPremium,
            createdAt: timestampString(from: local.createdAt)
        )

        let body = try jsonEncoder.encode([payload])
        let request = try await makeRequest(
            path: "rest/v1/daily_readings",
            method: "POST",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id,date,category")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )

        _ = try await performRequest(request)
    }

    // MARK: - Request Helpers

    private var isConfigured: Bool {
        baseURL != nil && !apiKey.isEmpty
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> URLRequest {
        guard let baseURL, !apiKey.isEmpty else {
            throw SyncError.invalidConfiguration
        }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SyncError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        let authToken = await resolveAuthToken()
        request.setValue("Bearer \(authToken ?? apiKey)", forHTTPHeaderField: "Authorization")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        return request
    }

    private func resolveAuthToken() async -> String? {
        let token = await authTokenProvider()
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw SyncError.requestFailed(statusCode: httpResponse.statusCode, body: responseBody)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw SyncError.decodingFailed
        }
    }

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        var delay = initialBackoffNanoseconds

        while true {
            do {
                return try await operation()
            } catch {
                attempt += 1
                if attempt >= maxAttempts || !shouldRetry(for: error) {
                    throw error
                }

                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, maxBackoffNanoseconds)
            }
        }
    }

    private func shouldRetry(for error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        guard case SyncError.requestFailed(let statusCode, _) = error else {
            return false
        }

        if statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 {
            return true
        }
        return (500...599).contains(statusCode)
    }

    // MARK: - Date Helpers

    private func dayString(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func timestampString(from date: Date) -> String {
        iso8601WithFractional.string(from: date)
    }

    private func parseDay(_ value: String) -> Date {
        dayFormatter.date(from: value) ?? .distantPast
    }

    private func parseTimestamp(_ value: String?) -> Date {
        guard let value, !value.isEmpty else { return .distantPast }
        if let parsed = iso8601WithFractional.date(from: value) {
            return parsed
        }
        if let parsed = iso8601.date(from: value) {
            return parsed
        }
        return .distantPast
    }
}

@available(iOS 17.0, macOS 14.0, *)
final class SyncBacklogStore {
    private struct QueuedOperation: Sendable {
        let id: UUID
        let type: PendingSyncOperationType
        let payload: Data
        let attempts: Int
    }

    private let modelContext: ModelContext
    private let syncService: SyncService
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let baseRetryDelay: TimeInterval = 30
    private let maxRetryDelay: TimeInterval = 15 * 60
    private let maxRetryAttempts = 288
    private let retentionWindow: TimeInterval = 14 * 24 * 60 * 60
    private let maxStoredOperations = 500

    init(modelContext: ModelContext, syncService: SyncService) {
        self.modelContext = modelContext
        self.syncService = syncService
    }

    func enqueueUserProfile(
        _ snapshot: SyncService.UserProfileSnapshot,
        failure: Error? = nil,
        failureReason: String? = nil
    ) async {
        await enqueue(
            type: .userProfile,
            dedupeKey: userProfileKey(snapshot.id),
            payload: snapshot,
            failure: failure,
            failureReason: failureReason
        )
    }

    func enqueueDailyReading(
        _ snapshot: SyncService.DailyReadingSnapshot,
        failure: Error? = nil,
        failureReason: String? = nil
    ) async {
        await enqueue(
            type: .dailyReading,
            dedupeKey: dailyReadingKey(
                userID: snapshot.userID,
                category: snapshot.categoryRawValue,
                date: snapshot.date
            ),
            payload: snapshot,
            failure: failure,
            failureReason: failureReason
        )
    }

    func clearUserProfile(_ userID: UUID) async {
        await clearOperation(dedupeKey: userProfileKey(userID))
    }

    func clearDailyReading(_ snapshot: SyncService.DailyReadingSnapshot) async {
        await clearOperation(
            dedupeKey: dailyReadingKey(
                userID: snapshot.userID,
                category: snapshot.categoryRawValue,
                date: snapshot.date
            )
        )
    }

    func migrateUserIdentity(from oldUserID: UUID, to newUserID: UUID) async {
        guard oldUserID != newUserID else { return }

        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>()
            let operations = (try? modelContext.fetch(descriptor)) ?? []
            guard !operations.isEmpty else { return }

            let now = Date()
            var didMutate = false

            for operation in operations {
                guard let operationType = PendingSyncOperationType(rawValue: operation.typeRawValue) else {
                    continue
                }

                switch operationType {
                case .userProfile:
                    guard operation.dedupeKey == userProfileKey(oldUserID) else {
                        continue
                    }

                    guard
                        let snapshot = try? jsonDecoder.decode(
                            SyncService.UserProfileSnapshot.self,
                            from: operation.payload
                        ),
                        let encoded = try? jsonEncoder.encode(
                            SyncService.UserProfileSnapshot(
                                id: newUserID,
                                name: snapshot.name,
                                birthdate: snapshot.birthdate,
                                zodiacSignRawValue: snapshot.zodiacSignRawValue,
                                mbtiTypeRawValue: snapshot.mbtiTypeRawValue,
                                createdAt: snapshot.createdAt,
                                updatedAt: snapshot.updatedAt
                            )
                        )
                    else {
                        continue
                    }

                    operation.payload = encoded
                    operation.dedupeKey = userProfileKey(newUserID)
                    operation.updatedAt = now
                    didMutate = true

                case .dailyReading:
                    guard
                        let snapshot = try? jsonDecoder.decode(
                            SyncService.DailyReadingSnapshot.self,
                            from: operation.payload
                        ),
                        snapshot.userID == oldUserID,
                        let encoded = try? jsonEncoder.encode(
                            SyncService.DailyReadingSnapshot(
                                id: snapshot.id,
                                userID: newUserID,
                                date: snapshot.date,
                                categoryRawValue: snapshot.categoryRawValue,
                                content: snapshot.content,
                                fortuneScore: snapshot.fortuneScore,
                                luckyNumbers: snapshot.luckyNumbers,
                                powerColors: snapshot.powerColors,
                                isPremium: snapshot.isPremium,
                                createdAt: snapshot.createdAt
                            )
                        )
                    else {
                        continue
                    }

                    operation.payload = encoded
                    operation.dedupeKey = dailyReadingKey(
                        userID: newUserID,
                        category: snapshot.categoryRawValue,
                        date: snapshot.date
                    )
                    operation.updatedAt = now
                    didMutate = true
                }
            }

            if didMutate {
                try? modelContext.save()
            }
        }
    }

    func processDueOperations(limit: Int = 20) async {
        await pruneBacklogIfNeeded()

        let queuedOperations = await loadDueOperations(limit: limit)
        guard !queuedOperations.isEmpty else { return }

        for queued in queuedOperations {
            do {
                switch queued.type {
                case .userProfile:
                    let snapshot = try jsonDecoder.decode(
                        SyncService.UserProfileSnapshot.self,
                        from: queued.payload
                    )
                    let outcome = try await syncService.syncUserProfile(snapshot)
                    switch outcome {
                    case .pushedLocal:
                        await clearOperation(id: queued.id)
                    case .remoteWins(let remote):
                        await applyRemoteProfile(remote, localUserID: snapshot.id)
                        await clearOperation(id: queued.id)
                    case .skippedConfiguration:
                        _ = await rescheduleOperation(
                            id: queued.id,
                            previousAttempts: queued.attempts,
                            message: "Sync service not configured."
                        )
                    }

                case .dailyReading:
                    let snapshot = try jsonDecoder.decode(
                        SyncService.DailyReadingSnapshot.self,
                        from: queued.payload
                    )
                    let outcome = try await syncService.syncDailyReading(snapshot)
                    switch outcome {
                    case .pushedLocal:
                        await clearOperation(id: queued.id)
                    case .remoteWins(let remote):
                        await applyRemoteReading(remote, localSnapshot: snapshot)
                        await clearOperation(id: queued.id)
                    case .skippedConfiguration:
                        _ = await rescheduleOperation(
                            id: queued.id,
                            previousAttempts: queued.attempts,
                            message: "Sync service not configured."
                        )
                    }
                }
            } catch {
                _ = await rescheduleOperation(
                    id: queued.id,
                    previousAttempts: queued.attempts,
                    message: errorDescription(for: error)
                )
            }
        }

        await pruneBacklogIfNeeded()
    }

    private func enqueue<T: Encodable>(
        type: PendingSyncOperationType,
        dedupeKey: String,
        payload: T,
        failure: Error?,
        failureReason: String?
    ) async {
        guard let encodedPayload = try? jsonEncoder.encode(payload) else { return }

        let now = Date()
        let errorMessage = failureReason ?? failure.map(errorDescription)
        let hasFailureSignal = errorMessage != nil
        let attempts = hasFailureSignal ? 1 : 0
        let nextRetryAt = hasFailureSignal
            ? now.addingTimeInterval(retryDelay(forAttempt: attempts))
            : now

        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.dedupeKey == dedupeKey
            })

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.type = type
                existing.payload = encodedPayload
                existing.attempts = attempts
                existing.nextRetryAt = nextRetryAt
                existing.lastError = errorMessage
                existing.updatedAt = now
            } else {
                let operation = PendingSyncOperation(
                    type: type,
                    dedupeKey: dedupeKey,
                    payload: encodedPayload,
                    attempts: attempts,
                    nextRetryAt: nextRetryAt,
                    lastError: errorMessage,
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(operation)
            }

            try? modelContext.save()
        }

        await pruneBacklogIfNeeded()
    }

    private func loadDueOperations(limit: Int) async -> [QueuedOperation] {
        await MainActor.run {
            let now = Date()
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.nextRetryAt <= now
            })

            let operations = (try? modelContext.fetch(descriptor)) ?? []
            let sorted = operations.sorted { lhs, rhs in
                if lhs.nextRetryAt == rhs.nextRetryAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.nextRetryAt < rhs.nextRetryAt
            }

            return sorted.prefix(max(1, limit)).compactMap { operation in
                guard let type = PendingSyncOperationType(rawValue: operation.typeRawValue) else {
                    return nil
                }
                return QueuedOperation(
                    id: operation.id,
                    type: type,
                    payload: operation.payload,
                    attempts: operation.attempts
                )
            }
        }
    }

    private func clearOperation(id: UUID) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.id == id
            })

            guard let operation = try? modelContext.fetch(descriptor).first else {
                return
            }

            modelContext.delete(operation)
            try? modelContext.save()
        }
    }

    private func clearOperation(dedupeKey: String) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.dedupeKey == dedupeKey
            })

            guard let operations = try? modelContext.fetch(descriptor), !operations.isEmpty else {
                return
            }

            for operation in operations {
                modelContext.delete(operation)
            }
            try? modelContext.save()
        }
    }

    private func rescheduleOperation(id: UUID, previousAttempts: Int, message: String) async -> Bool {
        let now = Date()
        let nextAttempts = previousAttempts + 1
        guard nextAttempts < maxRetryAttempts else {
            await dropOperation(id: id, message: message)
            return false
        }

        let retryAt = now.addingTimeInterval(retryDelay(forAttempt: nextAttempts))

        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.id == id
            })

            guard let operation = try? modelContext.fetch(descriptor).first else {
                return
            }

            operation.attempts = nextAttempts
            operation.lastError = message
            operation.nextRetryAt = retryAt
            operation.updatedAt = now
            try? modelContext.save()
        }

        return true
    }

    private func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        let step = max(0, attempt - 1)
        return min(pow(2, Double(step)) * baseRetryDelay, maxRetryDelay)
    }

    private func errorDescription(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private func userProfileKey(_ userID: UUID) -> String {
        "user:\(userID.uuidString)"
    }

    private func dailyReadingKey(userID: UUID, category: String, date: Date) -> String {
        "reading:\(userID.uuidString):\(category):\(dayKey(for: date))"
    }

    private func dayKey(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: .current, from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func pruneBacklogIfNeeded() async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>()
            guard let operations = try? modelContext.fetch(descriptor), !operations.isEmpty else {
                return
            }

            let now = Date()
            var didMutate = false

            for operation in operations {
                let operationAge = now.timeIntervalSince(operation.createdAt)
                if operationAge > retentionWindow || operation.attempts >= maxRetryAttempts {
                    modelContext.delete(operation)
                    didMutate = true
                }
            }

            let remaining = (try? modelContext.fetch(descriptor)) ?? []
            let overflow = remaining.count - maxStoredOperations
            if overflow > 0 {
                let sorted = remaining.sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.createdAt < rhs.createdAt
                }

                for operation in sorted.prefix(overflow) {
                    modelContext.delete(operation)
                    didMutate = true
                }
            }

            if didMutate {
                try? modelContext.save()
            }
        }
    }

    private func dropOperation(id: UUID, message: String) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<PendingSyncOperation>(predicate: #Predicate { operation in
                operation.id == id
            })

            guard let operation = try? modelContext.fetch(descriptor).first else {
                return
            }

            operation.lastError = message
            operation.updatedAt = Date()
            modelContext.delete(operation)
            try? modelContext.save()
        }
    }

    private func applyRemoteProfile(_ remote: SyncService.RemoteUserProfile, localUserID: UUID) async {
        await MainActor.run {
            let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { profile in
                profile.id == localUserID
            })

            guard let localProfile = try? modelContext.fetch(descriptor).first else {
                return
            }

            localProfile.name = remote.name
            if remote.birthdate.timeIntervalSince1970 > 0 {
                localProfile.birthdate = remote.birthdate
            }
            if let mbtiType = MBTIType(rawValue: remote.mbtiTypeRawValue) {
                localProfile.mbtiType = mbtiType
            }
            localProfile.updatedAt = remote.updatedAt
            try? modelContext.save()
        }
    }

    private func applyRemoteReading(
        _ remote: SyncService.RemoteDailyReading,
        localSnapshot: SyncService.DailyReadingSnapshot
    ) async {
        guard let category = SituationCategory(rawValue: localSnapshot.categoryRawValue) else {
            return
        }

        await MainActor.run {
            let calendar = Calendar.current
            let descriptor = FetchDescriptor<DailyReading>()

            guard let localReading = try? modelContext.fetch(descriptor).first(where: { reading in
                if reading.id == localSnapshot.id {
                    return true
                }
                guard let userID = reading.user?.id else { return false }
                guard reading.category == category else { return false }
                return userID == localSnapshot.userID
                    && calendar.isDate(reading.date, inSameDayAs: localSnapshot.date)
            }) else {
                return
            }

            localReading.content = DailyReadingContentGuardrails.sanitize(
                remote.content,
                isPremium: remote.isPremium
            )
            localReading.fortuneScore = remote.fortuneScore
            localReading.luckyNumbers = remote.luckyNumbers
            localReading.powerColors = remote.powerColors
            localReading.isPremium = remote.isPremium

            if remote.date.timeIntervalSince1970 > 0 {
                localReading.date = remote.date
            }
            if remote.createdAt.timeIntervalSince1970 > 0 {
                localReading.createdAt = remote.createdAt
            }

            try? modelContext.save()
        }
    }
}
