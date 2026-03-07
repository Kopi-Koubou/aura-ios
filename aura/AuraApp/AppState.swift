import SwiftUI
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
protocol UserProfileSyncing {
    func syncUserProfile(
        _ local: SyncService.UserProfileSnapshot
    ) async throws -> SyncService.UserProfileSyncOutcome
}

@available(iOS 17.0, macOS 14.0, *)
protocol UserProfileSyncBacklogging {
    func enqueueUserProfile(
        _ snapshot: SyncService.UserProfileSnapshot,
        failure: Error?,
        failureReason: String?
    ) async
    func clearUserProfile(_ userID: UUID) async
    func processDueOperations(limit: Int) async
    func migrateUserIdentity(from oldUserID: UUID, to newUserID: UUID) async
}

@available(iOS 17.0, macOS 14.0, *)
@Observable
final class AppState {
    var currentUser: UserProfile?
    var subscriptionStatus: SubscriptionStatus
    var isLoading = true
    var error: AppError?
    var contentService: ContentService?
    var hasAuthAccessToken = false
    var hasAuthRefreshToken = false
    var authSessionExpiresAt: Date?
    var authSessionStatusMessage = "No auth session configured"
    var authSessionLastRefreshError: String?
    var authSessionAuthenticatedUserID: String?
    var authSessionUserIDMismatch = false
    var isRefreshingAuthSession = false
    private var modelContext: ModelContext?
    private var syncService: UserProfileSyncing?
    private var syncBacklog: UserProfileSyncBacklogging?
    private let sessionManager: SupabaseSessionManager

    private enum IdentityReconciliationError: LocalizedError {
        case missingModelContext
        case missingLocalProfile
        case missingAuthenticatedUserID
        case invalidAuthenticatedUserID(String)

        var errorDescription: String? {
            switch self {
            case .missingModelContext:
                return "User data context is unavailable."
            case .missingLocalProfile:
                return "No local profile is available to reconcile."
            case .missingAuthenticatedUserID:
                return "Sign in before reconciling identity."
            case .invalidAuthenticatedUserID(let rawID):
                return "Authenticated user ID is not a valid UUID: \(rawID)"
            }
        }
    }

    init(
        sessionManager: SupabaseSessionManager = SupabaseSessionManager(
            supabaseURL: Secrets.supabaseURL,
            supabaseAnonKey: Secrets.supabaseAnonKey
        )
    ) {
        self.subscriptionStatus = SubscriptionStatus()
        self.sessionManager = sessionManager
    }

    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        let sessionManager = self.sessionManager
        let authTokenProvider: @Sendable () async -> String? = { [sessionManager] in
            await sessionManager.validAccessToken()
        }

        let openAI = OpenAIService(
            apiKey: Secrets.openAIKey,
            authTokenProvider: authTokenProvider
        )
        let syncService = SyncService(authTokenProvider: authTokenProvider)
        let syncBacklog = SyncBacklogStore(modelContext: modelContext, syncService: syncService)
        self.syncService = syncService
        self.syncBacklog = syncBacklog
        self.contentService = ContentService(
            modelContext: modelContext,
            openAIService: openAI,
            subscriptionManager: SubscriptionManager.shared,
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        Task(priority: .utility) { [syncBacklog] in
            await syncBacklog.processDueOperations(limit: 20)
        }

        Task { [weak self] in
            guard let self else { return }
            await self.refreshAuthSessionStatus()
        }
    }

    func configureProfileSyncDependenciesForTesting(
        syncService: UserProfileSyncing,
        syncBacklog: UserProfileSyncBacklogging
    ) {
        self.syncService = syncService
        self.syncBacklog = syncBacklog
    }

    func loadUser(modelContext: ModelContext) async {
        self.modelContext = modelContext
        isLoading = true
        defer { isLoading = false }

        let descriptor = FetchDescriptor<UserProfile>()
        do {
            if let user = try modelContext.fetch(descriptor).first {
                currentUser = user
                await SubscriptionManager.shared.identify(userId: user.id.uuidString)
                refreshAuthIdentityMismatch()
            }
        } catch {
            self.error = .failedToLoadUser
        }
    }

    func refreshSubscription() async {
        await SubscriptionManager.shared.refreshStatus()
        subscriptionStatus.tier = SubscriptionManager.shared.isPremium ? .premium : .free
        subscriptionStatus.isActive = SubscriptionManager.shared.isPremium
    }

    @MainActor
    func refreshAuthSessionStatus() async {
        updateSessionState(with: await sessionManager.snapshot())
    }

    @MainActor
    func refreshAuthSession() async {
        isRefreshingAuthSession = true
        defer { isRefreshingAuthSession = false }

        _ = await sessionManager.validAccessToken(forceRefresh: true)
        let snapshot = await sessionManager.snapshot()
        updateSessionState(with: snapshot)

        if !snapshot.hasAccessToken {
            error = .authFailed
        }
    }

    @MainActor
    func clearAuthSession() async {
        await sessionManager.clear()
        updateSessionState(with: await sessionManager.snapshot())
    }

    @MainActor
    func applyAuthSession(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date?
    ) async throws {
        try await sessionManager.replaceSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
        updateSessionState(with: await sessionManager.snapshot())
        try await reconcileAuthIdentityIfNeeded()
    }

    @MainActor
    func signInWithSupabase(email: String, password: String) async throws {
        _ = try await sessionManager.signInWithPassword(email: email, password: password)
        updateSessionState(with: await sessionManager.snapshot())
        try await reconcileAuthIdentityIfNeeded()
    }

    @MainActor
    func signUpWithSupabase(
        email: String,
        password: String
    ) async throws -> SupabaseSessionManager.SignUpOutcome {
        let outcome = try await sessionManager.signUpWithPassword(
            email: email,
            password: password
        )
        updateSessionState(with: await sessionManager.snapshot())
        if case .authenticated = outcome {
            try await reconcileAuthIdentityIfNeeded()
        }
        return outcome
    }

    @MainActor
    func requestSupabasePasswordReset(email: String) async throws {
        try await sessionManager.requestPasswordReset(email: email)
    }

    @MainActor
    func reconcileAuthIdentityWithLocalProfile() async throws {
        guard let modelContext else {
            throw IdentityReconciliationError.missingModelContext
        }
        guard let currentUser else {
            throw IdentityReconciliationError.missingLocalProfile
        }
        guard let authUserID = authSessionAuthenticatedUserID else {
            throw IdentityReconciliationError.missingAuthenticatedUserID
        }
        guard let authUserUUID = UUID(uuidString: authUserID) else {
            throw IdentityReconciliationError.invalidAuthenticatedUserID(authUserID)
        }

        if currentUser.id == authUserUUID {
            refreshAuthIdentityMismatch()
            return
        }

        let previousUserID = currentUser.id
        let descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { profile in
            profile.id == authUserUUID
        })

        let targetUser: UserProfile
        if let matchingProfile = try modelContext.fetch(descriptor).first {
            mergeLocalProfile(currentUser, into: matchingProfile)
            targetUser = matchingProfile
        } else {
            currentUser.id = authUserUUID
            currentUser.updatedAt = Date()
            targetUser = currentUser
        }

        try modelContext.save()
        self.currentUser = targetUser

        if previousUserID != targetUser.id {
            await syncBacklog?.migrateUserIdentity(from: previousUserID, to: targetUser.id)
        }

        await SubscriptionManager.shared.identify(userId: targetUser.id.uuidString)
        refreshAuthIdentityMismatch()
        enqueueProfileSync(targetUser)
    }

    @MainActor
    func completeOnboarding(name: String, birthdate: Date, mbtiType: MBTIType) async throws {
        guard let modelContext else {
            throw AppError.failedToCreateUser
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AppError.failedToCreateUser
        }

        let authenticatedUserUUID = await authenticatedUserUUIDFromSession()
        let profile: UserProfile

        if
            let authenticatedUserUUID,
            let existingProfile = try modelContext.fetch(
                FetchDescriptor<UserProfile>(predicate: #Predicate { profile in
                    profile.id == authenticatedUserUUID
                })
            ).first
        {
            existingProfile.name = trimmedName
            existingProfile.birthdate = birthdate
            existingProfile.mbtiType = mbtiType
            existingProfile.updatedAt = Date()
            profile = existingProfile
        } else {
            let createdProfile = UserProfile(name: trimmedName, birthdate: birthdate, mbtiType: mbtiType)
            if let authenticatedUserUUID {
                createdProfile.id = authenticatedUserUUID
            }
            modelContext.insert(createdProfile)
            profile = createdProfile
        }

        try modelContext.save()

        currentUser = profile
        await SubscriptionManager.shared.identify(userId: profile.id.uuidString)

        AnalyticsService.shared.identify(userId: profile.id, userProperties: [
            "zodiac_sign": profile.zodiacSign.rawValue,
            "mbti_type": profile.mbtiType.rawValue,
        ])
        AnalyticsService.shared.track(.appOpen, properties: ["source": "onboarding_complete"])

        refreshAuthIdentityMismatch()
        enqueueProfileSync(profile)
    }

    @MainActor
    private func reconcileAuthIdentityIfNeeded() async throws {
        guard currentUser != nil else {
            return
        }

        refreshAuthIdentityMismatch()
        guard authSessionUserIDMismatch else {
            return
        }

        try await reconcileAuthIdentityWithLocalProfile()
    }

    @MainActor
    private func authenticatedUserUUIDFromSession() async -> UUID? {
        let snapshot = await sessionManager.snapshot()
        updateSessionState(with: snapshot)

        guard let authenticatedUserID = snapshot.authenticatedUserID else {
            return nil
        }
        return UUID(uuidString: authenticatedUserID)
    }

    private func enqueueProfileSync(_ profile: UserProfile) {
        guard let syncService, let syncBacklog else { return }

        let snapshot = SyncService.UserProfileSnapshot(
            id: profile.id,
            name: profile.name,
            birthdate: profile.birthdate,
            zodiacSignRawValue: profile.zodiacSign.rawValue,
            mbtiTypeRawValue: profile.mbtiType.rawValue,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )

        Task(priority: .utility) { [weak self] in
            guard let self else { return }

            do {
                let outcome = try await syncService.syncUserProfile(snapshot)
                switch outcome {
                case .pushedLocal:
                    await syncBacklog.clearUserProfile(snapshot.id)
                case .remoteWins(let remote):
                    await syncBacklog.clearUserProfile(snapshot.id)
                    await MainActor.run {
                        self.applyRemoteProfile(remote, localUserID: snapshot.id)
                    }
                case .skippedConfiguration:
                    await syncBacklog.enqueueUserProfile(
                        snapshot,
                        failure: nil,
                        failureReason: "Sync service not configured."
                    )
                }
            } catch {
                await syncBacklog.enqueueUserProfile(
                    snapshot,
                    failure: error,
                    failureReason: nil
                )
                await MainActor.run {
                    self.error = .syncDeferred
                }
            }

            await syncBacklog.processDueOperations(limit: 10)
        }
    }

    @MainActor
    private func applyRemoteProfile(_ remote: SyncService.RemoteUserProfile, localUserID: UUID) {
        guard let modelContext else { return }

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

        do {
            try modelContext.save()
            if currentUser?.id == localProfile.id {
                currentUser = localProfile
            }
            refreshAuthIdentityMismatch()
        } catch {
            self.error = .syncDeferred
        }
    }

    @MainActor
    private func mergeLocalProfile(_ source: UserProfile, into target: UserProfile) {
        guard source.id != target.id else { return }

        if source.updatedAt >= target.updatedAt {
            target.name = source.name
            target.birthdate = source.birthdate
            target.mbtiType = source.mbtiType
            target.updatedAt = source.updatedAt
        }

        target.createdAt = min(target.createdAt, source.createdAt)

        if let sourceReadings = source.readings {
            for reading in sourceReadings {
                reading.user = target
            }
        }

        if let sourceMBTIResults = source.mbtiResults {
            for result in sourceMBTIResults {
                result.user = target
            }
        }

        modelContext?.delete(source)
    }

    @MainActor
    private func updateSessionState(with snapshot: SupabaseSessionManager.SessionSnapshot) {
        hasAuthAccessToken = snapshot.hasAccessToken
        hasAuthRefreshToken = snapshot.hasRefreshToken
        authSessionExpiresAt = snapshot.expiresAt
        authSessionLastRefreshError = snapshot.lastRefreshError
        authSessionAuthenticatedUserID = snapshot.authenticatedUserID
        authSessionStatusMessage = sessionStatusMessage(for: snapshot)
        refreshAuthIdentityMismatch()
    }

    private func sessionStatusMessage(for snapshot: SupabaseSessionManager.SessionSnapshot) -> String {
        if snapshot.hasAccessToken {
            if let expiresAt = snapshot.expiresAt, expiresAt <= Date() {
                return snapshot.hasRefreshToken ? "Session expired. Refresh available." : "Session expired."
            }
            return "Authenticated"
        }

        if snapshot.hasRefreshToken {
            return "Refresh token available (access token missing)"
        }

        return "No auth session configured"
    }

    private func refreshAuthIdentityMismatch() {
        guard
            let authUserID = authSessionAuthenticatedUserID,
            let currentUser
        else {
            authSessionUserIDMismatch = false
            return
        }

        authSessionUserIDMismatch = authUserID.caseInsensitiveCompare(currentUser.id.uuidString) != .orderedSame
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension SyncService: UserProfileSyncing {}

@available(iOS 17.0, macOS 14.0, *)
extension SyncBacklogStore: UserProfileSyncBacklogging {}

@available(iOS 17.0, macOS 14.0, *)
actor SupabaseSessionManager {
    struct SessionSnapshot: Sendable {
        let hasAccessToken: Bool
        let hasRefreshToken: Bool
        let expiresAt: Date?
        let lastRefreshError: String?
        let authenticatedUserID: String?
    }

    private struct RefreshSessionRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct PasswordSignInRequest: Encodable {
        let email: String
        let password: String
    }

    private struct PasswordSignUpRequest: Encodable {
        let email: String
        let password: String
    }

    private struct PasswordRecoveryRequest: Encodable {
        let email: String
    }

    private struct AuthUserPayload: Decodable {
        let id: String?
    }

    enum SignUpOutcome: Sendable {
        case authenticated(userID: String?)
        case confirmationRequired(userID: String?)
    }

    private struct SessionTokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let expiresAt: Double?
        let user: AuthUserPayload?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }

    private struct SignUpResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let expiresAt: Double?
        let user: AuthUserPayload?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }

    private enum SessionError: LocalizedError {
        case missingSessionCredentials
        case missingSignInCredentials
        case missingRecoveryEmail
        case missingRefreshToken
        case invalidConfiguration
        case invalidRefreshURL
        case invalidPasswordSignInURL
        case invalidPasswordSignUpURL
        case invalidPasswordRecoveryURL
        case invalidResponse
        case refreshRejected(statusCode: Int, body: String)
        case signInRejected(statusCode: Int, body: String)
        case signUpRejected(statusCode: Int, body: String)
        case passwordRecoveryRejected(statusCode: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .missingSessionCredentials:
                return "Provide at least an access token or refresh token."
            case .missingSignInCredentials:
                return "Email and password are required."
            case .missingRecoveryEmail:
                return "Email is required."
            case .missingRefreshToken:
                return "No refresh token is available."
            case .invalidConfiguration:
                return "Supabase auth session is not configured."
            case .invalidRefreshURL:
                return "Supabase refresh URL is invalid."
            case .invalidPasswordSignInURL:
                return "Supabase password sign-in URL is invalid."
            case .invalidPasswordSignUpURL:
                return "Supabase password sign-up URL is invalid."
            case .invalidPasswordRecoveryURL:
                return "Supabase password recovery URL is invalid."
            case .invalidResponse:
                return "Supabase returned an invalid auth response."
            case .refreshRejected(let statusCode, _):
                return "Supabase refresh failed with status \(statusCode)."
            case .signInRejected(let statusCode, _):
                return "Supabase sign-in failed with status \(statusCode)."
            case .signUpRejected(let statusCode, _):
                return "Supabase sign-up failed with status \(statusCode)."
            case .passwordRecoveryRejected(let statusCode, _):
                return "Supabase password reset request failed with status \(statusCode)."
            }
        }
    }

    private let supabaseURL: String
    private let supabaseAnonKey: String
    private let urlSession: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?
    private var lastRefreshError: String?
    private let refreshSkew: TimeInterval = 120

    init(
        supabaseURL: String,
        supabaseAnonKey: String,
        urlSession: URLSession = .shared
    ) {
        self.supabaseURL = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supabaseAnonKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
        self.accessToken = Self.normalize(Secrets.supabaseAccessToken)
        self.refreshToken = Self.normalize(Secrets.supabaseRefreshToken)
        self.expiresAt = Secrets.supabaseAccessTokenExpirationDate
    }

    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh, let accessToken, !isAccessTokenExpiringSoon() {
            return accessToken
        }

        guard refreshToken != nil else {
            if isAccessTokenExpired() {
                return nil
            }
            return accessToken
        }

        do {
            try await refreshSession()
            return accessToken
        } catch {
            lastRefreshError = error.localizedDescription
            if isAccessTokenExpired() {
                return nil
            }
            return accessToken
        }
    }

    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            hasAccessToken: accessToken != nil,
            hasRefreshToken: refreshToken != nil,
            expiresAt: expiresAt,
            lastRefreshError: lastRefreshError,
            authenticatedUserID: Self.jwtSubject(from: accessToken)
        )
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        lastRefreshError = nil
        persistSession()
    }

    func replaceSession(accessToken: String?, refreshToken: String?, expiresAt: Date?) throws {
        let normalizedAccessToken = Self.normalize(accessToken)
        let normalizedRefreshToken = Self.normalize(refreshToken)

        guard normalizedAccessToken != nil || normalizedRefreshToken != nil else {
            throw SessionError.missingSessionCredentials
        }

        self.accessToken = normalizedAccessToken
        self.refreshToken = normalizedRefreshToken
        self.expiresAt = expiresAt
        self.lastRefreshError = nil
        persistSession()
    }

    func signInWithPassword(email: String, password: String) async throws -> String? {
        guard
            let normalizedEmail = Self.normalize(email),
            let normalizedPassword = Self.normalize(password)
        else {
            throw SessionError.missingSignInCredentials
        }
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw SessionError.invalidConfiguration
        }
        guard let signInURL = authPasswordSignInURL() else {
            throw SessionError.invalidPasswordSignInURL
        }

        var request = URLRequest(url: signInURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            PasswordSignInRequest(
                email: normalizedEmail,
                password: normalizedPassword
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SessionError.signInRejected(statusCode: httpResponse.statusCode, body: body)
        }

        try applySessionTokenResponse(data, requireRefreshToken: true)
        lastRefreshError = nil
        persistSession()
        return Self.jwtSubject(from: accessToken)
    }

    func signUpWithPassword(email: String, password: String) async throws -> SignUpOutcome {
        guard
            let normalizedEmail = Self.normalize(email),
            let normalizedPassword = Self.normalize(password)
        else {
            throw SessionError.missingSignInCredentials
        }
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw SessionError.invalidConfiguration
        }
        guard let signUpURL = authPasswordSignUpURL() else {
            throw SessionError.invalidPasswordSignUpURL
        }

        var request = URLRequest(url: signUpURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            PasswordSignUpRequest(
                email: normalizedEmail,
                password: normalizedPassword
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SessionError.signUpRejected(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(SignUpResponse.self, from: data)
        let normalizedAccessToken = Self.normalize(decoded.accessToken)
        let normalizedRefreshToken = Self.normalize(decoded.refreshToken)

        if normalizedAccessToken != nil || normalizedRefreshToken != nil {
            try applySessionTokenPayload(
                accessToken: normalizedAccessToken,
                refreshToken: normalizedRefreshToken,
                expiresIn: decoded.expiresIn,
                expiresAt: decoded.expiresAt,
                requireRefreshToken: true
            )
            lastRefreshError = nil
            persistSession()
            let userID = Self.normalize(decoded.user?.id) ?? Self.jwtSubject(from: accessToken)
            return .authenticated(userID: userID)
        }

        return .confirmationRequired(userID: Self.normalize(decoded.user?.id))
    }

    func requestPasswordReset(email: String) async throws {
        guard let normalizedEmail = Self.normalize(email) else {
            throw SessionError.missingRecoveryEmail
        }
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw SessionError.invalidConfiguration
        }
        guard let passwordRecoveryURL = authPasswordRecoveryURL() else {
            throw SessionError.invalidPasswordRecoveryURL
        }

        var request = URLRequest(url: passwordRecoveryURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(
            PasswordRecoveryRequest(email: normalizedEmail)
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SessionError.passwordRecoveryRejected(statusCode: httpResponse.statusCode, body: body)
        }
    }

    private func refreshSession() async throws {
        guard let refreshToken else {
            throw SessionError.missingRefreshToken
        }
        guard !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty else {
            throw SessionError.invalidConfiguration
        }
        guard let refreshURL = authRefreshURL() else {
            throw SessionError.invalidRefreshURL
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(RefreshSessionRequest(refreshToken: refreshToken))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SessionError.refreshRejected(statusCode: httpResponse.statusCode, body: body)
        }

        try applySessionTokenResponse(data, requireRefreshToken: false)
        lastRefreshError = nil
        persistSession()
    }

    private func authRefreshURL() -> URL? {
        let trimmedBase = Self.trimmedBaseURL(supabaseURL)
        guard !trimmedBase.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/auth/v1/token?grant_type=refresh_token")
    }

    private func authPasswordSignInURL() -> URL? {
        let trimmedBase = Self.trimmedBaseURL(supabaseURL)
        guard !trimmedBase.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/auth/v1/token?grant_type=password")
    }

    private func authPasswordSignUpURL() -> URL? {
        let trimmedBase = Self.trimmedBaseURL(supabaseURL)
        guard !trimmedBase.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/auth/v1/signup")
    }

    private func authPasswordRecoveryURL() -> URL? {
        let trimmedBase = Self.trimmedBaseURL(supabaseURL)
        guard !trimmedBase.isEmpty else { return nil }
        return URL(string: "\(trimmedBase)/auth/v1/recover")
    }

    private func applySessionTokenResponse(_ data: Data, requireRefreshToken: Bool) throws {
        let decoded = try JSONDecoder().decode(SessionTokenResponse.self, from: data)
        try applySessionTokenPayload(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresIn: decoded.expiresIn,
            expiresAt: decoded.expiresAt,
            requireRefreshToken: requireRefreshToken
        )
    }

    private func applySessionTokenPayload(
        accessToken: String?,
        refreshToken: String?,
        expiresIn: Double?,
        expiresAt: Double?,
        requireRefreshToken: Bool
    ) throws {
        guard let normalizedAccessToken = Self.normalize(accessToken) else {
            throw SessionError.invalidResponse
        }

        let normalizedRefreshToken = Self.normalize(refreshToken)
        if requireRefreshToken && normalizedRefreshToken == nil {
            throw SessionError.invalidResponse
        }

        self.accessToken = normalizedAccessToken
        if let normalizedRefreshToken {
            self.refreshToken = normalizedRefreshToken
        }

        if let expiresAt {
            self.expiresAt = Date(timeIntervalSince1970: Self.normalizeEpoch(expiresAt))
        } else if let expiresIn, expiresIn > 0 {
            self.expiresAt = Date().addingTimeInterval(expiresIn)
        }
    }

    private func persistSession() {
        let defaults = UserDefaults.standard

        if let accessToken {
            defaults.set(accessToken, forKey: Secrets.supabaseAccessTokenDefaultsKey)
        } else {
            defaults.removeObject(forKey: Secrets.supabaseAccessTokenDefaultsKey)
        }

        if let refreshToken {
            defaults.set(refreshToken, forKey: Secrets.supabaseRefreshTokenDefaultsKey)
        } else {
            defaults.removeObject(forKey: Secrets.supabaseRefreshTokenDefaultsKey)
        }

        if let expiresAt {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: Secrets.supabaseAccessTokenExpiresAtDefaultsKey)
        } else {
            defaults.removeObject(forKey: Secrets.supabaseAccessTokenExpiresAtDefaultsKey)
        }
    }

    private func isAccessTokenExpiringSoon() -> Bool {
        guard let expiresAt else {
            return accessToken == nil
        }
        return expiresAt.timeIntervalSinceNow <= refreshSkew
    }

    private func isAccessTokenExpired() -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    private static func trimmedBaseURL(_ value: String) -> String {
        if value.hasSuffix("/") {
            return String(value.dropLast())
        }
        return value
    }

    private static func normalize(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizeEpoch(_ value: Double) -> Double {
        value > 10_000_000_000 ? (value / 1_000) : value
    }

    private static func jwtSubject(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard
            let payloadData = Data(base64Encoded: payload),
            let payloadJSON = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let subject = payloadJSON["sub"] as? String
        else {
            return nil
        }

        return normalize(subject)
    }
}
