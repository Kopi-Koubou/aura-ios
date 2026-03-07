import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
final class SecretsAuthModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearAuthModeOverride()
    }

    override func tearDown() {
        clearAuthModeOverride()
        super.tearDown()
    }

    func testParseGenerateHoroscopeAuthModeAcceptsSupportedValues() {
        XCTAssertEqual(Secrets.parseGenerateHoroscopeAuthMode("legacy"), .legacy)
        XCTAssertEqual(Secrets.parseGenerateHoroscopeAuthMode("AUDIT"), .audit)
        XCTAssertEqual(Secrets.parseGenerateHoroscopeAuthMode(" Enforce "), .enforce)
    }

    func testParseGenerateHoroscopeAuthModeRejectsUnsupportedValues() {
        XCTAssertNil(Secrets.parseGenerateHoroscopeAuthMode(nil))
        XCTAssertNil(Secrets.parseGenerateHoroscopeAuthMode(""))
        XCTAssertNil(Secrets.parseGenerateHoroscopeAuthMode("disabled"))
    }

    func testGenerateHoroscopeAuthModePrefersRuntimeOverride() {
        UserDefaults.standard.set("enforce", forKey: Secrets.generateHoroscopeAuthModeDefaultsKey)
        UserDefaults.standard.set(
            Secrets.currentAppBuildIdentifier,
            forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey
        )

        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .enforce)
        XCTAssertTrue(Secrets.requiresAuthenticatedOnboarding)
    }

    func testApplyGenerateHoroscopeAuthModeFromServerHeaderUpdatesRuntimeOverride() {
        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .audit)

        let applied = Secrets.applyGenerateHoroscopeAuthModeFromServerHeader("ENFORCE")

        XCTAssertEqual(applied, .enforce)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey),
            Secrets.GenerateHoroscopeAuthMode.enforce.rawValue
        )
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey),
            Secrets.currentAppBuildIdentifier
        )
        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .enforce)
        XCTAssertTrue(Secrets.requiresAuthenticatedOnboarding)
    }

    func testApplyGenerateHoroscopeAuthModeFromServerHeaderIgnoresUnsupportedValue() {
        UserDefaults.standard.set("legacy", forKey: Secrets.generateHoroscopeAuthModeDefaultsKey)
        UserDefaults.standard.set(
            Secrets.currentAppBuildIdentifier,
            forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey
        )

        let applied = Secrets.applyGenerateHoroscopeAuthModeFromServerHeader("unsupported")

        XCTAssertNil(applied)
        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .legacy)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey),
            Secrets.GenerateHoroscopeAuthMode.legacy.rawValue
        )
    }

    func testGenerateHoroscopeAuthModeClearsStaleRuntimeOverride() {
        UserDefaults.standard.set("enforce", forKey: Secrets.generateHoroscopeAuthModeDefaultsKey)
        UserDefaults.standard.set("stale-build", forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey)

        XCTAssertEqual(Secrets.generateHoroscopeAuthMode, .audit)
        XCTAssertNil(UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey))
        XCTAssertNil(UserDefaults.standard.string(forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey))
    }

    private func clearAuthModeOverride() {
        UserDefaults.standard.removeObject(forKey: Secrets.generateHoroscopeAuthModeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Secrets.generateHoroscopeAuthModeBuildDefaultsKey)
    }
}
