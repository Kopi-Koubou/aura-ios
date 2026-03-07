import Foundation
import SwiftData
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class IdentityReconciliationTests: XCTestCase {
    func testReconcileMergesIntoAuthenticatedProfileAndRelinksLocalData() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()

        let localBirthdate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        let authBirthdate = Date(timeIntervalSince1970: 662_688_000) // 1991-01-01
        let localUpdatedAt = Date(timeIntervalSince1970: 1_700_020_000)
        let authUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let localUser = UserProfile(name: "Local User", birthdate: localBirthdate, mbtiType: .INTJ)
        localUser.id = localUserID
        localUser.createdAt = Date(timeIntervalSince1970: 1_700_010_000)
        localUser.updatedAt = localUpdatedAt
        modelContext.insert(localUser)

        let reading = DailyReading(
            user: localUser,
            category: .love,
            content: "You will have a focused and productive day.",
            isPremium: true
        )
        modelContext.insert(reading)

        let mbtiResult = MBTIResult(
            typeCode: MBTIType.INTJ.rawValue,
            dimensionScores: [DimensionScore(dimension: "I", score: 0.8)]
        )
        mbtiResult.user = localUser
        modelContext.insert(mbtiResult)

        try modelContext.save()

        let appState = AppState(
            sessionManager: SupabaseSessionManager(
                supabaseURL: "https://example.supabase.co",
                supabaseAnonKey: "anon-key"
            )
        )
        await appState.loadUser(modelContext: modelContext)

        let authenticatedUser = UserProfile(name: "Auth User", birthdate: authBirthdate, mbtiType: .ENTP)
        authenticatedUser.id = authUserID
        authenticatedUser.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        authenticatedUser.updatedAt = authUpdatedAt
        modelContext.insert(authenticatedUser)
        try modelContext.save()

        appState.currentUser = localUser
        appState.authSessionAuthenticatedUserID = authUserID.uuidString.lowercased()
        appState.authSessionUserIDMismatch = true

        try await appState.reconcileAuthIdentityWithLocalProfile()

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, authUserID)

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)

        let updatedReading = try XCTUnwrap(
            try modelContext.fetch(FetchDescriptor<DailyReading>()).first
        )
        XCTAssertEqual(updatedReading.user?.id, authUserID)

        let updatedResult = try XCTUnwrap(
            try modelContext.fetch(FetchDescriptor<MBTIResult>()).first
        )
        XCTAssertEqual(updatedResult.user?.id, authUserID)

        let mergedUser = try XCTUnwrap(appState.currentUser)
        XCTAssertEqual(mergedUser.name, "Local User")
        XCTAssertEqual(mergedUser.birthdate, localBirthdate)
        XCTAssertEqual(mergedUser.mbtiType, .INTJ)
        XCTAssertEqual(mergedUser.updatedAt, localUpdatedAt)
        XCTAssertEqual(mergedUser.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMigrateUserIdentityRewritesQueuedPayloadsAndDedupeKeys() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncBacklog = SyncBacklogStore(
            modelContext: modelContext,
            syncService: SyncService(baseURL: "", apiKey: "")
        )
        let oldUserID = UUID()
        let newUserID = UUID()
        let readingDate = Date(timeIntervalSince1970: 1_700_000_000)

        let profileSnapshot = SyncService.UserProfileSnapshot(
            id: oldUserID,
            name: "Queued User",
            birthdate: Date(timeIntervalSince1970: 978_307_200),
            zodiacSignRawValue: ZodiacSign.capricorn.rawValue,
            mbtiTypeRawValue: MBTIType.ENTP.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let readingSnapshot = SyncService.DailyReadingSnapshot(
            id: UUID(),
            userID: oldUserID,
            date: readingDate,
            categoryRawValue: SituationCategory.career.rawValue,
            content: "Queued content",
            fortuneScore: 88,
            luckyNumbers: [8, 16, 24, 32, 40],
            powerColors: ["Gold", "Teal", "Sapphire"],
            isPremium: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_700)
        )

        await syncBacklog.enqueueUserProfile(profileSnapshot)
        await syncBacklog.enqueueDailyReading(readingSnapshot)
        await syncBacklog.migrateUserIdentity(from: oldUserID, to: newUserID)

        let operations = try modelContext.fetch(FetchDescriptor<PendingSyncOperation>())
        XCTAssertEqual(operations.count, 2)

        let migratedProfileOperation = try XCTUnwrap(
            operations.first { $0.type == .userProfile }
        )
        XCTAssertEqual(migratedProfileOperation.dedupeKey, "user:\(newUserID.uuidString)")

        let migratedProfilePayload = try JSONDecoder().decode(
            SyncService.UserProfileSnapshot.self,
            from: migratedProfileOperation.payload
        )
        XCTAssertEqual(migratedProfilePayload.id, newUserID)

        let migratedReadingOperation = try XCTUnwrap(
            operations.first { $0.type == .dailyReading }
        )
        XCTAssertEqual(
            migratedReadingOperation.dedupeKey,
            "reading:\(newUserID.uuidString):\(SituationCategory.career.rawValue):\(dayKey(for: readingDate))"
        )

        let migratedReadingPayload = try JSONDecoder().decode(
            SyncService.DailyReadingSnapshot.self,
            from: migratedReadingOperation.payload
        )
        XCTAssertEqual(migratedReadingPayload.userID, newUserID)
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

    private func dayKey(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: .current, from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
