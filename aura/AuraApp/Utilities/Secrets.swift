import Foundation

enum Secrets {
    static let supabaseAccessTokenDefaultsKey = "SUPABASE_ACCESS_TOKEN"
    static let supabaseRefreshTokenDefaultsKey = "SUPABASE_REFRESH_TOKEN"
    static let supabaseAccessTokenExpiresAtDefaultsKey = "SUPABASE_ACCESS_TOKEN_EXPIRES_AT"
    static let generateHoroscopeAuthModeDefaultsKey = "GENERATE_HOROSCOPE_AUTH_MODE"
    static let generateHoroscopeAuthModeBuildDefaultsKey = "GENERATE_HOROSCOPE_AUTH_MODE_SOURCE_BUILD"

    enum GenerateHoroscopeAuthMode: String {
        case legacy
        case audit
        case enforce

        var requiresAuthenticatedOnboarding: Bool {
            self == .enforce
        }
    }

    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }
    
    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }
    
    static var revenueCatAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
    }
    
    static var openAIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
    }

    static var posthogAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? ""
    }

    static var posthogHost: String {
        let custom = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String ?? ""
        return custom.isEmpty ? "https://app.posthog.com" : custom
    }

    static var supabaseAccessToken: String {
        let runtimeValue = UserDefaults.standard.string(forKey: supabaseAccessTokenDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let runtimeValue, !runtimeValue.isEmpty {
            return runtimeValue
        }

        let bundledValue = (Bundle.main.object(forInfoDictionaryKey: supabaseAccessTokenDefaultsKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundledValue
    }

    static var supabaseRefreshToken: String {
        let runtimeValue = UserDefaults.standard.string(forKey: supabaseRefreshTokenDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let runtimeValue, !runtimeValue.isEmpty {
            return runtimeValue
        }

        let bundledValue = (Bundle.main.object(forInfoDictionaryKey: supabaseRefreshTokenDefaultsKey) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return bundledValue
    }

    static var supabaseAccessTokenExpirationDate: Date? {
        if let runtimeDate = parseExpirationDate(UserDefaults.standard.object(forKey: supabaseAccessTokenExpiresAtDefaultsKey)) {
            return runtimeDate
        }
        return parseExpirationDate(Bundle.main.object(forInfoDictionaryKey: supabaseAccessTokenExpiresAtDefaultsKey))
    }

    static var generateHoroscopeAuthMode: GenerateHoroscopeAuthMode {
        let bundledMode = parseGenerateHoroscopeAuthMode(
            Bundle.main.object(forInfoDictionaryKey: generateHoroscopeAuthModeDefaultsKey) as? String
        ) ?? .audit

        let defaults = UserDefaults.standard
        let runtimeModeRaw = defaults.string(forKey: generateHoroscopeAuthModeDefaultsKey)
        let runtimeBuild = defaults.string(forKey: generateHoroscopeAuthModeBuildDefaultsKey)

        if
            let runtimeMode = parseGenerateHoroscopeAuthMode(runtimeModeRaw),
            let runtimeBuild,
            runtimeBuild == currentAppBuildIdentifier
        {
            return runtimeMode
        }

        if runtimeModeRaw != nil || runtimeBuild != nil {
            clearGenerateHoroscopeRuntimeOverride(defaults: defaults)
        }

        return bundledMode
    }

    static var requiresAuthenticatedOnboarding: Bool {
        generateHoroscopeAuthMode.requiresAuthenticatedOnboarding
    }

    @discardableResult
    static func applyGenerateHoroscopeAuthModeFromServerHeader(_ rawValue: String?) -> GenerateHoroscopeAuthMode? {
        guard let resolvedMode = parseGenerateHoroscopeAuthMode(rawValue) else {
            return nil
        }

        let defaults = UserDefaults.standard
        defaults.set(resolvedMode.rawValue, forKey: generateHoroscopeAuthModeDefaultsKey)
        defaults.set(currentAppBuildIdentifier, forKey: generateHoroscopeAuthModeBuildDefaultsKey)
        return resolvedMode
    }

    static var currentAppBuildIdentifier: String {
        let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [shortVersion, buildNumber]
            .filter { !$0.isEmpty }
            .joined(separator: "#")
        return combined.isEmpty ? "unknown" : combined
    }

    static func parseGenerateHoroscopeAuthMode(_ rawValue: String?) -> GenerateHoroscopeAuthMode? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return nil
        }

        return GenerateHoroscopeAuthMode(rawValue: normalized)
    }

    private static func parseExpirationDate(_ rawValue: Any?) -> Date? {
        guard let rawValue else { return nil }

        if let number = rawValue as? NSNumber {
            let seconds = number.doubleValue
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: normalizeEpoch(seconds))
        }

        guard let stringValue = rawValue as? String else {
            return nil
        }

        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let epoch = Double(trimmed), epoch > 0 {
            return Date(timeIntervalSince1970: normalizeEpoch(epoch))
        }

        if let parsed = fractionalISO8601.date(from: trimmed) {
            return parsed
        }
        if let parsed = internetISO8601.date(from: trimmed) {
            return parsed
        }

        return nil
    }

    private static func clearGenerateHoroscopeRuntimeOverride(defaults: UserDefaults) {
        defaults.removeObject(forKey: generateHoroscopeAuthModeDefaultsKey)
        defaults.removeObject(forKey: generateHoroscopeAuthModeBuildDefaultsKey)
    }

    private static func normalizeEpoch(_ value: Double) -> Double {
        // Treat 13-digit values as milliseconds.
        value > 10_000_000_000 ? (value / 1_000) : value
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internetISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
