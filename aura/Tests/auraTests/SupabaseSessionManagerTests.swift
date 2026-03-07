import Foundation
import XCTest
@testable import aura

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let queue = DispatchQueue(label: "URLProtocolStub.queue")

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
            client?.urlProtocol(self, didFailWithError: NSError(domain: "URLProtocolStub", code: -1))
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
final class SupabaseSessionManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPersistedSession()
        URLProtocolStub.setRequestHandler(nil)
    }

    override func tearDown() {
        URLProtocolStub.setRequestHandler(nil)
        clearPersistedSession()
        super.tearDown()
    }

    func testSignInWithPasswordPersistsSessionAndClearsRefreshError() async throws {
        let staleSubject = UUID().uuidString.lowercased()
        let expectedSubject = UUID().uuidString.lowercased()
        let staleAccessToken = makeJWT(subject: staleSubject)
        let freshAccessToken = makeJWT(subject: expectedSubject)
        let manager = makeManager()

        try await manager.replaceSession(
            accessToken: staleAccessToken,
            refreshToken: "stale-refresh-token",
            expiresAt: Date(timeIntervalSinceNow: -60)
        )

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("grant_type=refresh_token") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1001)
            }
            return Self.httpResponse(
                for: request,
                statusCode: 401,
                json: #"{"error":"refresh_denied"}"#
            )
        }

        _ = await manager.validAccessToken(forceRefresh: true)
        let afterRefresh = await manager.snapshot()
        XCTAssertNotNil(afterRefresh.lastRefreshError)

        let signInJSON = """
        {
          "access_token":"\(freshAccessToken)",
          "refresh_token":"fresh-refresh-token",
          "expires_in":3600,
          "user":{"id":"\(expectedSubject)"}
        }
        """

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("grant_type=password") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1002)
            }
            return Self.httpResponse(
                for: request,
                statusCode: 200,
                json: signInJSON
            )
        }

        let returnedSubject = try await manager.signInWithPassword(
            email: "test@example.com",
            password: "secure-password"
        )
        XCTAssertEqual(returnedSubject, expectedSubject)

        let snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasAccessToken)
        XCTAssertTrue(snapshot.hasRefreshToken)
        XCTAssertNil(snapshot.lastRefreshError)
        XCTAssertEqual(snapshot.authenticatedUserID, expectedSubject)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseAccessTokenDefaultsKey),
            freshAccessToken
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseRefreshTokenDefaultsKey),
            "fresh-refresh-token"
        )

        let rehydratedManager = makeManager()
        let rehydratedSnapshot = await rehydratedManager.snapshot()
        XCTAssertTrue(rehydratedSnapshot.hasAccessToken)
        XCTAssertTrue(rehydratedSnapshot.hasRefreshToken)
        XCTAssertEqual(rehydratedSnapshot.authenticatedUserID, expectedSubject)
    }

    func testSignInWithPasswordRejectsResponseWithoutRefreshToken() async throws {
        let existingSubject = UUID().uuidString.lowercased()
        let existingAccessToken = makeJWT(subject: existingSubject)
        let manager = makeManager()

        try await manager.replaceSession(
            accessToken: existingAccessToken,
            refreshToken: "existing-refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 1800)
        )

        let invalidSignInJSON = """
        {
          "access_token":"\(makeJWT(subject: UUID().uuidString.lowercased()))",
          "expires_in":3600
        }
        """

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("grant_type=password") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1003)
            }
            return Self.httpResponse(
                for: request,
                statusCode: 200,
                json: invalidSignInJSON
            )
        }

        do {
            _ = try await manager.signInWithPassword(
                email: "test@example.com",
                password: "secure-password"
            )
            XCTFail("Expected signInWithPassword to throw for missing refresh_token.")
        } catch {
            // Expected.
        }

        let snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasAccessToken)
        XCTAssertTrue(snapshot.hasRefreshToken)
        XCTAssertEqual(snapshot.authenticatedUserID, existingSubject)
        XCTAssertNil(snapshot.lastRefreshError)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseAccessTokenDefaultsKey),
            existingAccessToken
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseRefreshTokenDefaultsKey),
            "existing-refresh-token"
        )
    }

    func testSignUpWithPasswordPersistsSessionWhenTokensReturned() async throws {
        let expectedSubject = UUID().uuidString.lowercased()
        let accessToken = makeJWT(subject: expectedSubject)
        let manager = makeManager()

        let signUpJSON = """
        {
          "access_token":"\(accessToken)",
          "refresh_token":"fresh-signup-refresh-token",
          "expires_in":3600,
          "user":{"id":"\(expectedSubject)"}
        }
        """

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("/auth/v1/signup") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1004)
            }
            return Self.httpResponse(
                for: request,
                statusCode: 200,
                json: signUpJSON
            )
        }

        let outcome = try await manager.signUpWithPassword(
            email: "new-user@example.com",
            password: "secure-password"
        )

        switch outcome {
        case .authenticated(let userID):
            XCTAssertEqual(userID, expectedSubject)
        case .confirmationRequired:
            XCTFail("Expected authenticated outcome when signup returns session tokens.")
        }

        let snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasAccessToken)
        XCTAssertTrue(snapshot.hasRefreshToken)
        XCTAssertEqual(snapshot.authenticatedUserID, expectedSubject)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseAccessTokenDefaultsKey),
            accessToken
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseRefreshTokenDefaultsKey),
            "fresh-signup-refresh-token"
        )
    }

    func testSignUpWithPasswordConfirmationRequiredKeepsExistingSession() async throws {
        let existingSubject = UUID().uuidString.lowercased()
        let existingAccessToken = makeJWT(subject: existingSubject)
        let manager = makeManager()

        try await manager.replaceSession(
            accessToken: existingAccessToken,
            refreshToken: "existing-refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 1800)
        )

        let pendingSubject = UUID().uuidString.lowercased()
        let signUpJSON = """
        {
          "user":{"id":"\(pendingSubject)"}
        }
        """

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("/auth/v1/signup") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1005)
            }
            return Self.httpResponse(
                for: request,
                statusCode: 200,
                json: signUpJSON
            )
        }

        let outcome = try await manager.signUpWithPassword(
            email: "pending-user@example.com",
            password: "secure-password"
        )

        switch outcome {
        case .authenticated:
            XCTFail("Expected confirmationRequired when signup response omits session tokens.")
        case .confirmationRequired(let userID):
            XCTAssertEqual(userID, pendingSubject)
        }

        let snapshot = await manager.snapshot()
        XCTAssertTrue(snapshot.hasAccessToken)
        XCTAssertTrue(snapshot.hasRefreshToken)
        XCTAssertEqual(snapshot.authenticatedUserID, existingSubject)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseAccessTokenDefaultsKey),
            existingAccessToken
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.supabaseRefreshTokenDefaultsKey),
            "existing-refresh-token"
        )
    }

    func testRequestPasswordResetTargetsRecoverEndpoint() async throws {
        let manager = makeManager()
        var hitRecoverEndpoint = false

        URLProtocolStub.setRequestHandler { request in
            guard request.url?.absoluteString.contains("/auth/v1/recover") == true else {
                throw NSError(domain: "SupabaseSessionManagerTests", code: 1006)
            }
            hitRecoverEndpoint = true
            return Self.httpResponse(
                for: request,
                statusCode: 200,
                json: #"{}"#
            )
        }

        try await manager.requestPasswordReset(email: "recover@example.com")
        XCTAssertTrue(hitRecoverEndpoint)
    }

    private func makeManager() -> SupabaseSessionManager {
        SupabaseSessionManager(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            urlSession: makeStubbedURLSession()
        )
    }

    private func makeStubbedURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func clearPersistedSession() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Secrets.supabaseAccessTokenDefaultsKey)
        defaults.removeObject(forKey: Secrets.supabaseRefreshTokenDefaultsKey)
        defaults.removeObject(forKey: Secrets.supabaseAccessTokenExpiresAtDefaultsKey)
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
