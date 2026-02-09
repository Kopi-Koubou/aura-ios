import Foundation
import PostHog

enum AnalyticsEvent: String {
    case appOpen = "app_open"
    case readingViewed = "reading_viewed"
    case shareInitiated = "share_initiated"
    case shareCompleted = "share_completed"
    case paywallViewed = "paywall_viewed"
    case paywallDismissed = "paywall_dismissed"
    case subscriptionStarted = "subscription_started"
    case subscriptionCompleted = "subscription_completed"
    case referralCodeGenerated = "referral_code_generated"
    case referralCodeRedeemed = "referral_code_redeemed"
}

final class AnalyticsService {
    static let shared = AnalyticsService()

    private var isDebugMode: Bool = false
    private var isInitialized: Bool = false

    private init() {}

    func configure(apiKey: String, host: String = "https://app.posthog.com", debugMode: Bool = false) {
        self.isDebugMode = debugMode

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false

        if debugMode {
            config.debug = true
        }

        PostHogSDK.shared.setup(config)
        isInitialized = true

        if debugMode {
            print("[Analytics] PostHog initialized with host: \(host)")
        }
    }

    func identify(userId: UUID, userProperties: [String: Any]? = nil) {
        guard isInitialized else {
            logWarning("PostHog not initialized")
            return
        }

        let distinctId = userId.uuidString

        if let properties = userProperties {
            PostHogSDK.shared.identify(distinctId, userProperties: properties)
        } else {
            PostHogSDK.shared.identify(distinctId)
        }

        logDebug("Identified user: \(distinctId)")
    }

    func setUserProperties(zodiacSign: String? = nil, mbtiType: String? = nil, subscriptionStatus: String? = nil) {
        guard isInitialized else {
            logWarning("PostHog not initialized")
            return
        }

        var properties: [String: Any] = [:]

        if let zodiac = zodiacSign {
            properties["zodiac_sign"] = zodiac
        }
        if let mbti = mbtiType {
            properties["mbti_type"] = mbti
        }
        if let status = subscriptionStatus {
            properties["subscription_status"] = status
        }

        guard !properties.isEmpty else { return }

        PostHogSDK.shared.capture("$set", properties: ["$set": properties])
        logDebug("Set user properties: \(properties)")
    }

    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        track(event.rawValue, properties: properties)
    }

    func track(_ eventName: String, properties: [String: Any]? = nil) {
        guard isInitialized else {
            logWarning("PostHog not initialized")
            return
        }

        if let props = properties {
            PostHogSDK.shared.capture(eventName, properties: props)
        } else {
            PostHogSDK.shared.capture(eventName)
        }

        logDebug("Tracked event: \(eventName), properties: \(properties ?? [:])")
    }

    func reset() {
        guard isInitialized else { return }
        PostHogSDK.shared.reset()
        logDebug("Analytics session reset")
    }

    func flush() {
        guard isInitialized else { return }
        PostHogSDK.shared.flush()
        logDebug("Analytics flushed")
    }

    private func logDebug(_ message: String) {
        if isDebugMode {
            print("[Analytics] \(message)")
        }
    }

    private func logWarning(_ message: String) {
        if isDebugMode {
            print("[Analytics] ⚠️ \(message)")
        }
    }
}
