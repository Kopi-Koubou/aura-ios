import Foundation
import SwiftData
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class AppStateProfileSyncTests: XCTestCase {
    func testCompleteOnboardingPushedLocalClearsBacklogAndProcessesQueue() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncService = ProfileSyncServiceStub(response: .pushedLocal)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        try await appState.completeOnboarding(
            name: "Taylor",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()
        let userID = try XCTUnwrap(appState.currentUser?.id)
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.clearedUserIDs, [userID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])
        XCTAssertNil(appState.error)
    }

    func testCompleteOnboardingRemoteWinsAppliesRemoteProfile() async throws {
        let modelContext = try makeInMemoryModelContext()
        let remoteBirthdate = Date(timeIntervalSince1970: 662_688_000) // 1991-01-01
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let syncService = ProfileSyncServiceStub(
            response: .remoteWins(
                name: "Remote Name",
                birthdate: remoteBirthdate,
                mbtiType: .ENFP,
                updatedAt: remoteUpdatedAt
            )
        )
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        try await appState.completeOnboarding(
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let userID = try XCTUnwrap(appState.currentUser?.id)
        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let refreshedUser = try XCTUnwrap(users.first(where: { $0.id == userID }))
        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.clearedUserIDs, [userID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(refreshedUser.name, "Remote Name")
        XCTAssertEqual(refreshedUser.birthdate, remoteBirthdate)
        XCTAssertEqual(refreshedUser.mbtiType, .ENFP)
        XCTAssertEqual(refreshedUser.updatedAt, remoteUpdatedAt)
    }

    func testCompleteOnboardingSyncErrorEnqueuesBacklogAndSetsDeferredError() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncService = ProfileSyncServiceStub(response: .failure)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        try await appState.completeOnboarding(
            name: "Taylor",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(syncCalls, 1)
        XCTAssertTrue(state.clearedUserIDs.isEmpty)
        XCTAssertEqual(state.enqueuedOperations.count, 1)
        XCTAssertTrue(state.enqueuedOperations[0].hadFailure)
        XCTAssertNil(state.enqueuedOperations[0].failureReason)
        XCTAssertEqual(state.processedLimits, [10])

        guard case .syncDeferred? = appState.error else {
            return XCTFail("Expected syncDeferred error after sync failure.")
        }
    }

    func testCompleteOnboardingUsesAuthenticatedSessionUserIDWhenAvailable() async throws {
        let modelContext = try makeInMemoryModelContext()
        let syncService = ProfileSyncServiceStub(response: .pushedLocal)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()
        let authenticatedUserID = UUID()

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        try await appState.applyAuthSession(
            accessToken: makeJWT(subject: authenticatedUserID.uuidString.lowercased()),
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )

        try await appState.completeOnboarding(
            name: "Taylor",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let profile = try XCTUnwrap(appState.currentUser)
        let state = await syncBacklog.state()
        let latestSnapshot = await syncService.latestSyncedSnapshot()
        let syncedSnapshot = try XCTUnwrap(latestSnapshot)

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, authenticatedUserID)
        XCTAssertEqual(profile.id, authenticatedUserID)
        XCTAssertEqual(syncedSnapshot.id, authenticatedUserID)
        XCTAssertEqual(state.clearedUserIDs, [authenticatedUserID])
        XCTAssertTrue(state.migratedPairs.isEmpty)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testApplyAuthSessionAutomaticallyReconcilesIdentityMismatch() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authenticatedUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .pushedLocal)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try seedLocalUser(
            modelContext: modelContext,
            userID: localUserID,
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )

        try await appState.applyAuthSession(
            accessToken: makeJWT(subject: authenticatedUserID.uuidString.lowercased()),
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )

        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let reconciledUser = try XCTUnwrap(users.first(where: { $0.id == authenticatedUserID }))
        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(reconciledUser.id, authenticatedUserID)
        XCTAssertEqual(appState.currentUser?.id, authenticatedUserID)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authenticatedUserID)
        XCTAssertEqual(state.clearedUserIDs, [authenticatedUserID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentityRemoteWinsAppliesRemoteProfileAndMigratesBacklog() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let remoteBirthdate = Date(timeIntervalSince1970: 662_688_000) // 1991-01-01
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let syncService = ProfileSyncServiceStub(
            response: .remoteWins(
                name: "Remote Name",
                birthdate: remoteBirthdate,
                mbtiType: .ENFP,
                updatedAt: remoteUpdatedAt
            )
        )
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try seedLocalUser(
            modelContext: modelContext,
            userID: localUserID,
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )
        appState.authSessionAuthenticatedUserID = authUserID.uuidString.lowercased()
        appState.authSessionUserIDMismatch = true

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let reconciledUser = try XCTUnwrap(users.first(where: { $0.id == authUserID }))
        let state = await syncBacklog.state()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(reconciledUser.name, "Remote Name")
        XCTAssertEqual(reconciledUser.birthdate, remoteBirthdate)
        XCTAssertEqual(reconciledUser.mbtiType, .ENFP)
        XCTAssertEqual(reconciledUser.updatedAt, remoteUpdatedAt)

        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertEqual(state.clearedUserIDs, [authUserID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentitySkippedConfigurationEnqueuesBacklogWithoutError() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .skippedConfiguration)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try seedLocalUser(
            modelContext: modelContext,
            userID: localUserID,
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )
        appState.authSessionAuthenticatedUserID = authUserID.uuidString.lowercased()
        appState.authSessionUserIDMismatch = true

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()

        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertTrue(state.clearedUserIDs.isEmpty)
        XCTAssertEqual(state.enqueuedOperations.count, 1)
        XCTAssertEqual(state.enqueuedOperations[0].userID, authUserID)
        XCTAssertFalse(state.enqueuedOperations[0].hadFailure)
        XCTAssertEqual(state.enqueuedOperations[0].failureReason, "Sync service not configured.")
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentitySyncErrorEnqueuesFailureAndSetsDeferredError() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .failure)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try seedLocalUser(
            modelContext: modelContext,
            userID: localUserID,
            name: "Local Name",
            birthdate: Date(timeIntervalSince1970: 915_148_800),
            mbtiType: .INTJ
        )

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )
        appState.authSessionAuthenticatedUserID = authUserID.uuidString.lowercased()
        appState.authSessionUserIDMismatch = true

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()

        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertTrue(state.clearedUserIDs.isEmpty)
        XCTAssertEqual(state.enqueuedOperations.count, 1)
        XCTAssertEqual(state.enqueuedOperations[0].userID, authUserID)
        XCTAssertTrue(state.enqueuedOperations[0].hadFailure)
        XCTAssertNil(state.enqueuedOperations[0].failureReason)
        XCTAssertEqual(state.processedLimits, [10])

        guard case .syncDeferred? = appState.error else {
            return XCTFail("Expected syncDeferred error after reconciliation sync failure.")
        }
    }

    func testReconcileAuthIdentityMergeBranchPushedLocalKeepsMergedLocalProfileAndClearsBacklog() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .pushedLocal)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try await configureMergeBranchReconciliation(
            modelContext: modelContext,
            appState: appState,
            syncService: syncService,
            syncBacklog: syncBacklog,
            localUserID: localUserID,
            authUserID: authUserID
        )

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let mergedUser = try XCTUnwrap(users.first(where: { $0.id == authUserID }))
        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(mergedUser.name, "Local Name")
        XCTAssertEqual(mergedUser.birthdate, Date(timeIntervalSince1970: 915_148_800))
        XCTAssertEqual(mergedUser.mbtiType, .INTJ)
        XCTAssertEqual(mergedUser.updatedAt, Date(timeIntervalSince1970: 1_700_000_200))
        XCTAssertEqual(mergedUser.createdAt, Date(timeIntervalSince1970: 1_699_999_000))

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertEqual(state.clearedUserIDs, [authUserID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentityMergeBranchAuthenticatedProfileNewerKeepsAuthenticatedFieldsAndClearsBacklog() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .pushedLocal)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        let localCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let localUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let authCreatedAt = Date(timeIntervalSince1970: 1_699_999_000)
        let authUpdatedAt = Date(timeIntervalSince1970: 1_700_000_900)
        let authBirthdate = Date(timeIntervalSince1970: 662_688_000)

        try await configureMergeBranchReconciliation(
            modelContext: modelContext,
            appState: appState,
            syncService: syncService,
            syncBacklog: syncBacklog,
            localUserID: localUserID,
            authUserID: authUserID,
            localName: "Older Local",
            localBirthdate: Date(timeIntervalSince1970: 915_148_800),
            localMBTIType: .INTJ,
            localCreatedAt: localCreatedAt,
            localUpdatedAt: localUpdatedAt,
            authenticatedName: "Authenticated Winner",
            authenticatedBirthdate: authBirthdate,
            authenticatedMBTIType: .ENFP,
            authenticatedCreatedAt: authCreatedAt,
            authenticatedUpdatedAt: authUpdatedAt
        )

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let mergedUser = try XCTUnwrap(users.first(where: { $0.id == authUserID }))
        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()
        let latestSnapshot = await syncService.latestSyncedSnapshot()
        let syncedSnapshot = try XCTUnwrap(latestSnapshot)

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(mergedUser.name, "Authenticated Winner")
        XCTAssertEqual(mergedUser.birthdate, authBirthdate)
        XCTAssertEqual(mergedUser.mbtiType, .ENFP)
        XCTAssertEqual(mergedUser.updatedAt, authUpdatedAt)
        XCTAssertEqual(mergedUser.createdAt, authCreatedAt)

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertEqual(state.clearedUserIDs, [authUserID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(syncedSnapshot.id, authUserID)
        XCTAssertEqual(syncedSnapshot.name, "Authenticated Winner")
        XCTAssertEqual(syncedSnapshot.birthdate, authBirthdate)
        XCTAssertEqual(syncedSnapshot.mbtiTypeRawValue, MBTIType.ENFP.rawValue)
        XCTAssertEqual(syncedSnapshot.createdAt, authCreatedAt)
        XCTAssertEqual(syncedSnapshot.updatedAt, authUpdatedAt)

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentityMergeBranchRemoteWinsAppliesRemoteProfileAndClearsBacklog() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let remoteBirthdate = Date(timeIntervalSince1970: 662_688_000) // 1991-01-01
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_700_000_800)
        let syncService = ProfileSyncServiceStub(
            response: .remoteWins(
                name: "Remote Override",
                birthdate: remoteBirthdate,
                mbtiType: .ENFP,
                updatedAt: remoteUpdatedAt
            )
        )
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try await configureMergeBranchReconciliation(
            modelContext: modelContext,
            appState: appState,
            syncService: syncService,
            syncBacklog: syncBacklog,
            localUserID: localUserID,
            authUserID: authUserID
        )

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        let reconciledUser = try XCTUnwrap(users.first(where: { $0.id == authUserID }))
        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(reconciledUser.name, "Remote Override")
        XCTAssertEqual(reconciledUser.birthdate, remoteBirthdate)
        XCTAssertEqual(reconciledUser.mbtiType, .ENFP)
        XCTAssertEqual(reconciledUser.updatedAt, remoteUpdatedAt)

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertEqual(state.clearedUserIDs, [authUserID])
        XCTAssertTrue(state.enqueuedOperations.isEmpty)
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentityMergeBranchSkippedConfigurationEnqueuesBacklogWithoutError() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .skippedConfiguration)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try await configureMergeBranchReconciliation(
            modelContext: modelContext,
            appState: appState,
            syncService: syncService,
            syncBacklog: syncBacklog,
            localUserID: localUserID,
            authUserID: authUserID
        )

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertTrue(state.clearedUserIDs.isEmpty)
        XCTAssertEqual(state.enqueuedOperations.count, 1)
        XCTAssertEqual(state.enqueuedOperations[0].userID, authUserID)
        XCTAssertFalse(state.enqueuedOperations[0].hadFailure)
        XCTAssertEqual(state.enqueuedOperations[0].failureReason, "Sync service not configured.")
        XCTAssertEqual(state.processedLimits, [10])

        XCTAssertEqual(appState.currentUser?.id, authUserID)
        XCTAssertFalse(appState.authSessionUserIDMismatch)
        XCTAssertNil(appState.error)
    }

    func testReconcileAuthIdentityMergeBranchSyncErrorEnqueuesFailureAndSetsDeferredError() async throws {
        let modelContext = try makeInMemoryModelContext()
        let localUserID = UUID()
        let authUserID = UUID()
        let syncService = ProfileSyncServiceStub(response: .failure)
        let syncBacklog = ProfileSyncBacklogStub()
        let appState = makeAppState()

        try await configureMergeBranchReconciliation(
            modelContext: modelContext,
            appState: appState,
            syncService: syncService,
            syncBacklog: syncBacklog,
            localUserID: localUserID,
            authUserID: authUserID
        )

        try await appState.reconcileAuthIdentityWithLocalProfile()
        try await waitForProfileSyncToFinish(syncService: syncService, syncBacklog: syncBacklog)

        let state = await syncBacklog.state()
        let syncCalls = await syncService.syncCallCount()

        XCTAssertEqual(syncCalls, 1)
        XCTAssertEqual(state.migratedPairs.count, 1)
        XCTAssertEqual(state.migratedPairs.first?.0, localUserID)
        XCTAssertEqual(state.migratedPairs.first?.1, authUserID)
        XCTAssertTrue(state.clearedUserIDs.isEmpty)
        XCTAssertEqual(state.enqueuedOperations.count, 1)
        XCTAssertEqual(state.enqueuedOperations[0].userID, authUserID)
        XCTAssertTrue(state.enqueuedOperations[0].hadFailure)
        XCTAssertNil(state.enqueuedOperations[0].failureReason)
        XCTAssertEqual(state.processedLimits, [10])

        guard case .syncDeferred? = appState.error else {
            return XCTFail("Expected syncDeferred error after merge-branch reconciliation sync failure.")
        }
    }

    private func makeAppState() -> AppState {
        AppState(
            sessionManager: SupabaseSessionManager(
                supabaseURL: "https://example.supabase.co",
                supabaseAnonKey: "anon-key"
            )
        )
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

    private func seedLocalUser(
        modelContext: ModelContext,
        userID: UUID,
        name: String,
        birthdate: Date,
        mbtiType: MBTIType,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_200)
    ) throws {
        let localUser = UserProfile(name: name, birthdate: birthdate, mbtiType: mbtiType)
        localUser.id = userID
        localUser.createdAt = createdAt
        localUser.updatedAt = updatedAt
        modelContext.insert(localUser)
        try modelContext.save()
    }

    private func seedAuthenticatedUser(
        modelContext: ModelContext,
        userID: UUID,
        name: String,
        birthdate: Date,
        mbtiType: MBTIType,
        createdAt: Date = Date(timeIntervalSince1970: 1_699_999_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_050)
    ) throws {
        let authenticatedUser = UserProfile(name: name, birthdate: birthdate, mbtiType: mbtiType)
        authenticatedUser.id = userID
        authenticatedUser.createdAt = createdAt
        authenticatedUser.updatedAt = updatedAt
        modelContext.insert(authenticatedUser)
        try modelContext.save()
    }

    private func configureMergeBranchReconciliation(
        modelContext: ModelContext,
        appState: AppState,
        syncService: ProfileSyncServiceStub,
        syncBacklog: ProfileSyncBacklogStub,
        localUserID: UUID,
        authUserID: UUID,
        localName: String = "Local Name",
        localBirthdate: Date = Date(timeIntervalSince1970: 915_148_800),
        localMBTIType: MBTIType = .INTJ,
        localCreatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        localUpdatedAt: Date = Date(timeIntervalSince1970: 1_700_000_200),
        authenticatedName: String = "Auth Name",
        authenticatedBirthdate: Date = Date(timeIntervalSince1970: 662_688_000),
        authenticatedMBTIType: MBTIType = .ENFP,
        authenticatedCreatedAt: Date = Date(timeIntervalSince1970: 1_699_999_000),
        authenticatedUpdatedAt: Date = Date(timeIntervalSince1970: 1_700_000_050)
    ) async throws {
        try seedLocalUser(
            modelContext: modelContext,
            userID: localUserID,
            name: localName,
            birthdate: localBirthdate,
            mbtiType: localMBTIType,
            createdAt: localCreatedAt,
            updatedAt: localUpdatedAt
        )
        try seedAuthenticatedUser(
            modelContext: modelContext,
            userID: authUserID,
            name: authenticatedName,
            birthdate: authenticatedBirthdate,
            mbtiType: authenticatedMBTIType,
            createdAt: authenticatedCreatedAt,
            updatedAt: authenticatedUpdatedAt
        )

        await appState.loadUser(modelContext: modelContext)
        appState.configureProfileSyncDependenciesForTesting(
            syncService: syncService,
            syncBacklog: syncBacklog
        )
        appState.currentUser = try fetchUser(modelContext: modelContext, userID: localUserID)
        appState.authSessionAuthenticatedUserID = authUserID.uuidString.lowercased()
        appState.authSessionUserIDMismatch = true
    }

    private func fetchUser(modelContext: ModelContext, userID: UUID) throws -> UserProfile {
        let users = try modelContext.fetch(FetchDescriptor<UserProfile>())
        return try XCTUnwrap(users.first(where: { $0.id == userID }))
    }

    private func waitForProfileSyncToFinish(
        syncService: ProfileSyncServiceStub,
        syncBacklog: ProfileSyncBacklogStub,
        timeout: TimeInterval = 2.0
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let syncCalls = await syncService.syncCallCount()
            let processedCalls = await syncBacklog.state().processedLimits.count
            if syncCalls > 0 && processedCalls > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for background profile sync task to finish.")
    }

    private func makeJWT(subject: String) -> String {
        let header = base64URL([
            "alg": "none",
            "typ": "JWT",
        ])
        let payload = base64URL([
            "sub": subject,
        ])
        return "\(header).\(payload).signature"
    }

    private func base64URL(_ object: [String: String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@available(iOS 17.0, macOS 14.0, *)
private actor ProfileSyncServiceStub: UserProfileSyncing {
    enum Response {
        case pushedLocal
        case remoteWins(name: String, birthdate: Date, mbtiType: MBTIType, updatedAt: Date)
        case skippedConfiguration
        case failure
    }

    private enum StubError: Error {
        case failed
    }

    private let response: Response
    private var syncedSnapshots: [SyncService.UserProfileSnapshot] = []

    init(response: Response) {
        self.response = response
    }

    func syncUserProfile(
        _ local: SyncService.UserProfileSnapshot
    ) async throws -> SyncService.UserProfileSyncOutcome {
        syncedSnapshots.append(local)

        switch response {
        case .pushedLocal:
            return .pushedLocal
        case .remoteWins(let name, let birthdate, let mbtiType, let updatedAt):
            return .remoteWins(
                SyncService.RemoteUserProfile(
                    id: local.id,
                    name: name,
                    birthdate: birthdate,
                    zodiacSignRawValue: local.zodiacSignRawValue,
                    mbtiTypeRawValue: mbtiType.rawValue,
                    updatedAt: updatedAt
                )
            )
        case .skippedConfiguration:
            return .skippedConfiguration
        case .failure:
            throw StubError.failed
        }
    }

    func syncCallCount() -> Int {
        syncedSnapshots.count
    }

    func latestSyncedSnapshot() -> SyncService.UserProfileSnapshot? {
        syncedSnapshots.last
    }
}

@available(iOS 17.0, macOS 14.0, *)
private actor ProfileSyncBacklogStub: UserProfileSyncBacklogging {
    struct EnqueuedOperation: Sendable {
        let userID: UUID
        let hadFailure: Bool
        let failureReason: String?
    }

    struct State: Sendable {
        let clearedUserIDs: [UUID]
        let enqueuedOperations: [EnqueuedOperation]
        let processedLimits: [Int]
        let migratedPairs: [(UUID, UUID)]
    }

    private var clearedUserIDs: [UUID] = []
    private var enqueuedOperations: [EnqueuedOperation] = []
    private var processedLimits: [Int] = []
    private var migratedPairs: [(UUID, UUID)] = []

    func enqueueUserProfile(
        _ snapshot: SyncService.UserProfileSnapshot,
        failure: Error?,
        failureReason: String?
    ) async {
        enqueuedOperations.append(
            EnqueuedOperation(
                userID: snapshot.id,
                hadFailure: failure != nil,
                failureReason: failureReason
            )
        )
    }

    func clearUserProfile(_ userID: UUID) async {
        clearedUserIDs.append(userID)
    }

    func processDueOperations(limit: Int) async {
        processedLimits.append(limit)
    }

    func migrateUserIdentity(from oldUserID: UUID, to newUserID: UUID) async {
        migratedPairs.append((oldUserID, newUserID))
    }

    func state() -> State {
        State(
            clearedUserIDs: clearedUserIDs,
            enqueuedOperations: enqueuedOperations,
            processedLimits: processedLimits,
            migratedPairs: migratedPairs
        )
    }
}
