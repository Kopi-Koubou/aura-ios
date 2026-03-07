import Foundation
import SwiftData
import XCTest
@testable import aura

private final class BacklogURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let queue = DispatchQueue(label: "BacklogURLProtocolStub.queue")

    static func setRequestHandler(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        queue.sync {
            requestHandler = handler
        }
    }

    private static func handler() -> ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        queue.sync { requestHandler }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler() else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "BacklogURLProtocolStub", code: -1))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class SyncBacklogStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BacklogURLProtocolStub.setRequestHandler(nil)
    }

    override func tearDown() {
        BacklogURLProtocolStub.setRequestHandler(nil)
        super.tearDown()
    }

    func testProcessDueOperationsAppliesRemoteProfileAndClearsOperation() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let userID = UUID()
        let localUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_700_000_900)

        let localUser = UserProfile(
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 978_307_200),
            mbtiType: .INTJ
        )
        localUser.id = userID
        localUser.updatedAt = localUpdatedAt
        modelContext.insert(localUser)
        try modelContext.save()

        let snapshot = SyncService.UserProfileSnapshot(
            id: userID,
            name: localUser.name,
            birthdate: localUser.birthdate,
            zodiacSignRawValue: localUser.zodiacSign.rawValue,
            mbtiTypeRawValue: localUser.mbtiType.rawValue,
            createdAt: localUser.createdAt,
            updatedAt: localUser.updatedAt
        )

        await syncBacklog.enqueueUserProfile(snapshot)

        let remoteBirthdate = "1994-05-10"
        BacklogURLProtocolStub.setRequestHandler { request in
            guard
                request.httpMethod == "GET",
                request.url?.path == "/rest/v1/users"
            else {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }

            let body = """
            [{
              "id":"\(userID.uuidString)",
              "name":"Remote Name",
              "birthdate":"\(remoteBirthdate)",
              "zodiac_sign":"taurus",
              "mbti_type":"ENFP",
              "updated_at":"\(Self.isoTimestamp(remoteUpdatedAt))"
            }]
            """
            return Self.httpResponse(for: request, statusCode: 200, json: body)
        }

        await syncBacklog.processDueOperations(limit: 5)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let refreshedUser = try XCTUnwrap(users.first { $0.id == userID })
        XCTAssertEqual(refreshedUser.name, "Remote Name")
        XCTAssertEqual(refreshedUser.mbtiType, .ENFP)
        XCTAssertEqual(dayKey(for: refreshedUser.birthdate), remoteBirthdate)
        XCTAssertEqual(refreshedUser.updatedAt, remoteUpdatedAt)

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    func testProcessDueOperationsAppliesRemotePremiumReadingAndClearsOperation() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Reading User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INFJ
        )
        modelContext.insert(user)

        let localReading = DailyReading(
            user: user,
            category: .career,
            content: "Local free reading",
            isPremium: false
        )
        let readingDate = Date(timeIntervalSince1970: 1_700_430_400) // 2023-11-20T12:00:00Z
        localReading.date = readingDate
        localReading.createdAt = Date(timeIntervalSince1970: 1_700_430_000)
        localReading.fortuneScore = 61
        localReading.luckyNumbers = [1, 2, 3, 4, 5]
        localReading.powerColors = ["Gray", "White", "Black"]
        modelContext.insert(localReading)
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: localReading.id,
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.career.rawValue,
            content: localReading.content,
            fortuneScore: localReading.fortuneScore,
            luckyNumbers: localReading.luckyNumbers,
            powerColors: localReading.powerColors,
            isPremium: false,
            createdAt: localReading.createdAt
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        let remoteCreatedAt = Date(timeIntervalSince1970: 1_700_420_000)
        BacklogURLProtocolStub.setRequestHandler { request in
            guard
                request.httpMethod == "GET",
                request.url?.path == "/rest/v1/daily_readings"
            else {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }

            let body = """
            [{
              "id":"\(localReading.id.uuidString)",
              "user_id":"\(user.id.uuidString)",
              "date":"\(self.dayKey(for: readingDate))",
              "category":"\(SituationCategory.career.rawValue)",
              "content":"Remote premium reading",
              "fortune_score":95,
              "lucky_numbers":[11,22,33,44,55],
              "power_colors":["Gold","Teal","Sapphire"],
              "is_premium":true,
              "created_at":"\(Self.isoTimestamp(remoteCreatedAt))"
            }]
            """
            return Self.httpResponse(for: request, statusCode: 200, json: body)
        }

        await syncBacklog.processDueOperations(limit: 5)

        let readings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let refreshedReading = try XCTUnwrap(readings.first { $0.id == localReading.id })
        XCTAssertEqual(refreshedReading.content, "Remote premium reading")
        XCTAssertEqual(refreshedReading.fortuneScore, 95)
        XCTAssertEqual(refreshedReading.luckyNumbers, [11, 22, 33, 44, 55])
        XCTAssertEqual(refreshedReading.powerColors, ["Gold", "Teal", "Sapphire"])
        XCTAssertTrue(refreshedReading.isPremium)
        XCTAssertEqual(refreshedReading.createdAt, remoteCreatedAt)

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    func testProcessDueOperationsSanitizesOversizedRemoteFreeReadingContent() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Sanitize User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INFJ
        )
        modelContext.insert(user)

        let localReading = DailyReading(
            user: user,
            category: .social,
            content: "Local content",
            isPremium: false
        )
        let readingDate = Date(timeIntervalSince1970: 1_700_430_400)
        localReading.date = readingDate
        localReading.createdAt = Date(timeIntervalSince1970: 1_700_430_000)
        modelContext.insert(localReading)
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: localReading.id,
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.social.rawValue,
            content: localReading.content,
            fortuneScore: localReading.fortuneScore,
            luckyNumbers: localReading.luckyNumbers,
            powerColors: localReading.powerColors,
            isPremium: false,
            createdAt: localReading.createdAt
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        let remoteCreatedAt = Date(timeIntervalSince1970: 1_700_440_000)
        let oversizedRemoteContent = (1...220).map { "word\($0)" }.joined(separator: " ")

        BacklogURLProtocolStub.setRequestHandler { request in
            guard
                request.httpMethod == "GET",
                request.url?.path == "/rest/v1/daily_readings"
            else {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }

            let body = """
            [{
              "id":"\(localReading.id.uuidString)",
              "user_id":"\(user.id.uuidString)",
              "date":"\(self.dayKey(for: readingDate))",
              "category":"\(SituationCategory.social.rawValue)",
              "content":"\(oversizedRemoteContent)",
              "fortune_score":82,
              "lucky_numbers":[5,15,25,35,45],
              "power_colors":["Teal","Sapphire","Gold"],
              "is_premium":false,
              "created_at":"\(Self.isoTimestamp(remoteCreatedAt))"
            }]
            """
            return Self.httpResponse(for: request, statusCode: 200, json: body)
        }

        await syncBacklog.processDueOperations(limit: 5)

        let readings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let refreshedReading = try XCTUnwrap(readings.first { $0.id == localReading.id })
        XCTAssertEqual(refreshedReading.content.split(whereSeparator: \.isWhitespace).count, 150)
        XCTAssertEqual(refreshedReading.fortuneScore, 82)
    }

    func testProcessDueOperationsUsesFallbackForBlankRemoteReadingContent() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Blank Content User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .ISFP
        )
        modelContext.insert(user)

        let localReading = DailyReading(
            user: user,
            category: .health,
            content: "Local content",
            isPremium: false
        )
        let readingDate = Date(timeIntervalSince1970: 1_700_430_400)
        localReading.date = readingDate
        localReading.createdAt = Date(timeIntervalSince1970: 1_700_430_000)
        modelContext.insert(localReading)
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: localReading.id,
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.health.rawValue,
            content: localReading.content,
            fortuneScore: localReading.fortuneScore,
            luckyNumbers: localReading.luckyNumbers,
            powerColors: localReading.powerColors,
            isPremium: false,
            createdAt: localReading.createdAt
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        let remoteCreatedAt = Date(timeIntervalSince1970: 1_700_440_000)

        BacklogURLProtocolStub.setRequestHandler { request in
            guard
                request.httpMethod == "GET",
                request.url?.path == "/rest/v1/daily_readings"
            else {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }

            let body = """
            [{
              "id":"\(localReading.id.uuidString)",
              "user_id":"\(user.id.uuidString)",
              "date":"\(self.dayKey(for: readingDate))",
              "category":"\(SituationCategory.health.rawValue)",
              "content":"   ",
              "fortune_score":72,
              "lucky_numbers":[2,12,22,32,42],
              "power_colors":["Green","Blue","Silver"],
              "is_premium":false,
              "created_at":"\(Self.isoTimestamp(remoteCreatedAt))"
            }]
            """
            return Self.httpResponse(for: request, statusCode: 200, json: body)
        }

        await syncBacklog.processDueOperations(limit: 5)

        let readings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let refreshedReading = try XCTUnwrap(readings.first { $0.id == localReading.id })
        XCTAssertEqual(
            refreshedReading.content,
            "Cosmic signals are subtle today. Focus on one meaningful action and let consistency build your momentum."
        )
        XCTAssertEqual(refreshedReading.fortuneScore, 72)
    }

    func testProcessDueOperationsBreaksTimestampTieByPreferringRemoteWhenRemoteIDSortsAfterLocal() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Tie Break User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )
        modelContext.insert(user)

        let localID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let remoteID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let sharedCreatedAt = Date(timeIntervalSince1970: 1_700_430_000)
        let readingDate = Date(timeIntervalSince1970: 1_700_430_400)

        let localReading = DailyReading(
            user: user,
            category: .career,
            content: "Local tie loser",
            isPremium: false
        )
        localReading.id = localID
        localReading.date = readingDate
        localReading.createdAt = sharedCreatedAt
        localReading.fortuneScore = 61
        localReading.luckyNumbers = [3, 6, 9, 12, 15]
        localReading.powerColors = ["Gray", "Blue", "Silver"]
        modelContext.insert(localReading)
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: localReading.id,
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.career.rawValue,
            content: localReading.content,
            fortuneScore: localReading.fortuneScore,
            luckyNumbers: localReading.luckyNumbers,
            powerColors: localReading.powerColors,
            isPremium: false,
            createdAt: localReading.createdAt
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        let requestQueue = DispatchQueue(label: "SyncBacklogStoreTests.requestTracker")
        var didUpsertLocal = false

        BacklogURLProtocolStub.setRequestHandler { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/rest/v1/daily_readings"):
                let body = """
                [{
                  "id":"\(remoteID.uuidString)",
                  "user_id":"\(user.id.uuidString)",
                  "date":"\(self.dayKey(for: readingDate))",
                  "category":"\(SituationCategory.career.rawValue)",
                  "content":"Remote tie winner",
                  "fortune_score":89,
                  "lucky_numbers":[8,16,24,32,40],
                  "power_colors":["Gold","Teal","Sapphire"],
                  "is_premium":false,
                  "created_at":"\(Self.isoTimestamp(sharedCreatedAt))"
                }]
                """
                return Self.httpResponse(for: request, statusCode: 200, json: body)
            case ("POST", "/rest/v1/daily_readings"):
                requestQueue.sync {
                    didUpsertLocal = true
                }
                return Self.httpResponse(for: request, statusCode: 201, json: "[]")
            default:
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }
        }

        await syncBacklog.processDueOperations(limit: 5)

        let readings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let refreshedReading = try XCTUnwrap(readings.first { $0.id == localReading.id })
        XCTAssertEqual(refreshedReading.content, "Remote tie winner")
        XCTAssertEqual(refreshedReading.fortuneScore, 89)
        XCTAssertFalse(requestQueue.sync { didUpsertLocal })

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    func testProcessDueOperationsBreaksTimestampTieByKeepingLocalWhenRemoteIDSortsBeforeLocal() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Tie Break Local User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .ISTP
        )
        modelContext.insert(user)

        let localID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-00000000000f"))
        let remoteID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-00000000000e"))
        let sharedCreatedAt = Date(timeIntervalSince1970: 1_700_430_000)
        let readingDate = Date(timeIntervalSince1970: 1_700_430_400)

        let localReading = DailyReading(
            user: user,
            category: .social,
            content: "Local tie winner",
            isPremium: false
        )
        localReading.id = localID
        localReading.date = readingDate
        localReading.createdAt = sharedCreatedAt
        localReading.fortuneScore = 73
        localReading.luckyNumbers = [7, 17, 27, 37, 47]
        localReading.powerColors = ["Green", "Blue", "Silver"]
        modelContext.insert(localReading)
        try modelContext.save()

        let snapshot = SyncService.DailyReadingSnapshot(
            id: localReading.id,
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.social.rawValue,
            content: localReading.content,
            fortuneScore: localReading.fortuneScore,
            luckyNumbers: localReading.luckyNumbers,
            powerColors: localReading.powerColors,
            isPremium: false,
            createdAt: localReading.createdAt
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        let requestQueue = DispatchQueue(label: "SyncBacklogStoreTests.localPushTracker")
        var didUpsertLocal = false

        BacklogURLProtocolStub.setRequestHandler { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/rest/v1/daily_readings"):
                let body = """
                [{
                  "id":"\(remoteID.uuidString)",
                  "user_id":"\(user.id.uuidString)",
                  "date":"\(self.dayKey(for: readingDate))",
                  "category":"\(SituationCategory.social.rawValue)",
                  "content":"Remote tie loser",
                  "fortune_score":84,
                  "lucky_numbers":[4,14,24,34,44],
                  "power_colors":["Teal","Sapphire","Gold"],
                  "is_premium":false,
                  "created_at":"\(Self.isoTimestamp(sharedCreatedAt))"
                }]
                """
                return Self.httpResponse(for: request, statusCode: 200, json: body)
            case ("POST", "/rest/v1/daily_readings"):
                requestQueue.sync {
                    didUpsertLocal = true
                }
                return Self.httpResponse(for: request, statusCode: 201, json: "[]")
            default:
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }
        }

        await syncBacklog.processDueOperations(limit: 5)

        let readings = try modelContext.fetch(FetchDescriptor<DailyReading>())
        let refreshedReading = try XCTUnwrap(readings.first { $0.id == localReading.id })
        XCTAssertEqual(refreshedReading.content, "Local tie winner")
        XCTAssertEqual(refreshedReading.fortuneScore, 73)
        XCTAssertTrue(requestQueue.sync { didUpsertLocal })

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertTrue(operations.isEmpty)
    }

    func testProcessDueOperationsFailureReschedulesOperation() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: makeSyncService()
        )

        let user = UserProfile(
            name: "Retry User",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .ENTP
        )
        modelContext.insert(user)

        let readingDate = Date(timeIntervalSince1970: 1_700_430_400)
        let snapshot = SyncService.DailyReadingSnapshot(
            id: UUID(),
            userID: user.id,
            date: readingDate,
            categoryRawValue: SituationCategory.health.rawValue,
            content: "Retry me",
            fortuneScore: 70,
            luckyNumbers: [7, 14, 21, 28, 35],
            powerColors: ["Blue", "Green", "Silver"],
            isPremium: false,
            createdAt: Date(timeIntervalSince1970: 1_700_430_000)
        )

        await syncBacklog.enqueueDailyReading(snapshot)

        BacklogURLProtocolStub.setRequestHandler { request in
            guard request.url?.path == "/rest/v1/daily_readings" else {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"unexpected_request"}"#
                )
            }
            return Self.httpResponse(
                for: request,
                statusCode: 400,
                json: #"{"error":"bad_request"}"#
            )
        }

        let startedAt = Date()
        await syncBacklog.processDueOperations(limit: 1)

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertEqual(operations.count, 1)

        let operation = try XCTUnwrap(operations.first)
        XCTAssertEqual(operation.type, .dailyReading)
        XCTAssertEqual(operation.attempts, 1)
        XCTAssertGreaterThan(operation.nextRetryAt.timeIntervalSince(startedAt), 20)
        XCTAssertTrue((operation.lastError ?? "").contains("400"))
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: UserProfile.self,
            DailyReading.self,
            MBTIResult.self,
            PendingSyncOperation.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeSyncService() -> SyncService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BacklogURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)

        return SyncService(
            baseURL: "https://example.supabase.co",
            apiKey: "anon-key",
            urlSession: urlSession,
            authTokenProvider: { @Sendable () async -> String? in
                nil
            }
        )
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }
}
