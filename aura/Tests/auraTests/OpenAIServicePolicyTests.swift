import Foundation
import XCTest
@testable import aura

private final class OpenAIServiceURLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var requests: [URLRequest] = []
    private static let queue = DispatchQueue(label: "OpenAIServiceURLProtocolStub.queue")

    static func setRequestHandler(_ handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?) {
        queue.sync {
            requestHandler = handler
        }
    }

    static func reset() {
        queue.sync {
            requestHandler = nil
            requests.removeAll()
        }
    }

    static func capturedRequests() -> [URLRequest] {
        queue.sync { requests }
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
        Self.queue.sync {
            Self.requests.append(request)
        }

        guard let handler = Self.handler() else {
            client?.urlProtocol(
                self,
                didFailWithError: NSError(
                    domain: "OpenAIServiceURLProtocolStub",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing request handler"]
                )
            )
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
final class OpenAIServicePolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearAuthModeOverride()
        OpenAIServiceURLProtocolStub.reset()
    }

    override func tearDown() {
        OpenAIServiceURLProtocolStub.reset()
        clearAuthModeOverride()
        super.tearDown()
    }

    func testGenerateHoroscopeEdge429ThrowsAndSkipsDirectFallback() async throws {
        let service = makeService()
        let userID = UUID()

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 429,
                    json: #"{"error":"rate limited"}"#
                )
            }

            if request.url?.host == "api.openai.com" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    json: #"{"choices":[{"message":{"content":"Should not be requested."}}]}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        do {
            _ = try await service.generateHoroscope(
                userID: userID,
                zodiacSign: .aries,
                mbtiType: .INTJ,
                category: .career,
                isPremium: false
            )
            XCTFail("Expected edge 429 to throw and skip direct generation fallback.")
        } catch let error as OpenAIError {
            guard case .apiError(let statusCode, _) = error else {
                return XCTFail("Expected apiError, got \(error)")
            }
            XCTAssertEqual(statusCode, 429)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/functions/v1/generate-horoscope" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 0)
    }

    func testGenerateHoroscopeEdge500FallsBackToLocalTemplateAndSkipsDirectOpenAI() async throws {
        let service = makeService()
        let userID = UUID()
        let expectedContent = "Today favors your Love focus. As a ENFP virgo, trust your pattern-recognition and take one concrete step before the day ends. Small momentum now will compound quickly."

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 500,
                    json: #"{"error":"edge unavailable"}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        let generated = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .virgo,
            mbtiType: .ENFP,
            category: .love,
            isPremium: true
        )

        XCTAssertEqual(generated, expectedContent)

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/functions/v1/generate-horoscope" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 0)
    }

    func testGenerateHoroscopeUsesDirectOpenAIWhenEdgeConfigurationMissing() async throws {
        let service = makeService(supabaseURL: "", supabaseAnonKey: "")
        let userID = UUID()
        let expectedContent = "Direct fallback content from OpenAI."

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.host == "api.openai.com" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    json: #"{"choices":[{"message":{"content":"Direct fallback content from OpenAI."}}]}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        let generated = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .virgo,
            mbtiType: .ENFP,
            category: .love,
            isPremium: true
        )

        XCTAssertEqual(generated, expectedContent)

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/functions/v1/generate-horoscope" }.count, 0)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 1)
    }

    func testGenerateHoroscopeAddsAuthorizationHeaderWhenTokenProviderReturnsToken() async throws {
        let service = makeService(
            authTokenProvider: { @Sendable () async -> String? in
                "  test-access-token  "
            }
        )
        let userID = UUID()
        let expectedContent = "Edge generated content."

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    json: #"{"reading":{"content":"Edge generated content."}}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        let generated = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .aries,
            mbtiType: .INTJ,
            category: .career,
            isPremium: false
        )

        XCTAssertEqual(generated, expectedContent)

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 0)

        let edgeRequest = try XCTUnwrap(
            requests.first { $0.url?.path == "/functions/v1/generate-horoscope" }
        )
        XCTAssertEqual(edgeRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
    }

    func testGenerateHoroscopeUsesProvidedDateForEdgePayloadAndCacheKey() async throws {
        let service = makeService()
        let userID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let firstDate = try XCTUnwrap(dayFormatter.date(from: "2026-03-05"))
        let secondDate = try XCTUnwrap(dayFormatter.date(from: "2026-03-06"))

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    json: #"{"reading":{"content":"Edge generated content."}}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        _ = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .social,
            isPremium: false,
            date: firstDate
        )
        _ = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .social,
            isPremium: false,
            date: secondDate
        )
        _ = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .social,
            isPremium: false,
            date: firstDate
        )

        let edgeRequests = OpenAIServiceURLProtocolStub
            .capturedRequests()
            .filter { $0.url?.path == "/functions/v1/generate-horoscope" }

        XCTAssertEqual(edgeRequests.count, 2)
        XCTAssertEqual(try edgeRequestDate(from: edgeRequests[0]), "2026-03-05")
        XCTAssertEqual(try edgeRequestDate(from: edgeRequests[1]), "2026-03-06")
    }

    func testGenerateHoroscopeEnforcesCharacterLimitOnEdgeResponses() async throws {
        let service = makeService()
        let userID = UUID()
        let oversizedToken = String(repeating: "x", count: 6_000)

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                let payload = try JSONSerialization.data(
                    withJSONObject: ["reading": ["content": oversizedToken]],
                    options: []
                )
                return Self.httpResponse(for: request, statusCode: 200, data: payload)
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        let generated = try await service.generateHoroscope(
            userID: userID,
            zodiacSign: .leo,
            mbtiType: .ENTJ,
            category: .health,
            isPremium: true
        )

        XCTAssertEqual(generated.count, 5_000)

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/functions/v1/generate-horoscope" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 0)
    }

    func testGenerateHoroscopePersistsAuthModeFromEdgeFailureHeaders() async throws {
        let service = makeService()
        let userID = UUID()

        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .audit)

        OpenAIServiceURLProtocolStub.setRequestHandler { request in
            if request.url?.path == "/functions/v1/generate-horoscope" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 401,
                    headers: [
                        "x-aura-auth-mode": "enforce",
                        "x-aura-auth-context": "missing",
                        "x-aura-auth-fallback": "0"
                    ],
                    json: #"{"error":"Authorization bearer token is required"}"#
                )
            }

            if request.url?.host == "api.openai.com" {
                return Self.httpResponse(
                    for: request,
                    statusCode: 200,
                    json: #"{"choices":[{"message":{"content":"Should not be requested."}}]}"#
                )
            }

            return Self.httpResponse(for: request, statusCode: 500, json: #"{"error":"unexpected_request"}"#)
        }

        do {
            _ = try await service.generateHoroscope(
                userID: userID,
                zodiacSign: .scorpio,
                mbtiType: .INFJ,
                category: .health,
                isPremium: false
            )
            XCTFail("Expected edge 401 to throw and preserve edge policy.")
        } catch let error as OpenAIError {
            guard case .apiError(let statusCode, _) = error else {
                return XCTFail("Expected apiError, got \(error)")
            }
            XCTAssertEqual(statusCode, 401)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .enforce)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey),
            Secrets.GenerateHoroscopeAuthMode.enforce.rawValue
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey),
            Secrets.currentAppBuildIdentifier
        )

        let requests = OpenAIServiceURLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/functions/v1/generate-horoscope" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.openai.com" }.count, 0)
    }

    private func makeService(
        supabaseURL: String = "https://example.supabase.co",
        supabaseAnonKey: String = "supabase-anon-key",
        authTokenProvider: @escaping @Sendable () async -> String? = { nil }
    ) -> OpenAIService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAIServiceURLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        return OpenAIService(
            apiKey: "openai-test-key",
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            session: session,
            authTokenProvider: authTokenProvider
        )
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        json: String
    ) -> (HTTPURLResponse, Data) {
        httpResponse(for: request, statusCode: statusCode, headers: headers, data: Data(json.utf8))
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:],
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers.merging(["Content-Type": "application/json"]) { _, new in new }
        )!
        return (response, data)
    }

    private func clearAuthModeOverride() {
        UserDefaults.standard.removeObject(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey)
    }

    private func edgeRequestDate(from request: URLRequest) throws -> String {
        let body = try requestBodyData(from: request)
        let jsonObject = try JSONSerialization.jsonObject(with: body)
        let payload = try XCTUnwrap(jsonObject as? [String: Any])
        return try XCTUnwrap(payload["date"] as? String)
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw NSError(
                domain: "OpenAIServicePolicyTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Request body is unavailable"]
            )
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw stream.streamError ?? NSError(
                    domain: "OpenAIServicePolicyTests",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to read request body stream"]
                )
            }
            if bytesRead == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }

        return data
    }
}
