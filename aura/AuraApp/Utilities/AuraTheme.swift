import SwiftUI
#if os(iOS)
import UIKit
import UserNotifications
#endif

@available(iOS 17.0, macOS 14.0, *)
struct AuraTheme {
    let colorScheme: ColorScheme

    var accent: Color {
        Color(red: 0.83, green: 0.39, blue: 0.19)
    }

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.1)
            : Color(red: 0.972, green: 0.967, blue: 0.949)
    }

    var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.16)
            : .white
    }

    var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    var iconFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var rowFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }

    var mutedIcon: Color {
        colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25)
    }

    var fieldBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
    }

    func accentFill(prominent: Bool = false) -> Color {
        accent.opacity(colorScheme == .dark ? 0.2 : (prominent ? 0.14 : 0.12))
    }

    func tintFill(for color: Color) -> Color {
        color.opacity(colorScheme == .dark ? 0.20 : 0.12)
    }

    func subtleFill() -> Color {
        accent.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }

    func accentBorder() -> Color {
        accent.opacity(colorScheme == .dark ? 0.4 : 0.3)
    }

    var chipBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    var subtleBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
    }

    var zodiacIconBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.98, green: 0.93, blue: 0.88)
    }

    func chipSurface(stacked: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(stacked ? 0.1 : 0.12)
        }
        return Color.white.opacity(stacked ? 0.96 : 0.9)
    }

    // MARK: - Semantic Text Colors

    var textPrimary: Color {
        colorScheme == .dark
            ? Color(red: 0.93, green: 0.93, blue: 0.93)
            : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    var textSecondary: Color {
        colorScheme == .dark
            ? Color(red: 0.63, green: 0.63, blue: 0.63)
            : Color(red: 0.43, green: 0.42, blue: 0.40)
    }

    // MARK: - Semantic Tints

    static let retrogradeAmber = Color(red: 0.78, green: 0.46, blue: 0.09)

    static let destructiveRed = Color(red: 0.86, green: 0.15, blue: 0.15)

    var errorTint: Color {
        Color(red: 0.72, green: 0.34, blue: 0.25)
    }

    func streakTint(for streak: Int) -> Color {
        switch streak {
        case 7...:
            return Color(red: 0.85, green: 0.45, blue: 0.12)
        case 3...:
            return Color(red: 0.78, green: 0.46, blue: 0.17)
        default:
            return accent
        }
    }

    // MARK: - Score Tints

    static func scoreTint(for score: Int) -> Color {
        switch score {
        case 85...:
            return Color(red: 0.16, green: 0.58, blue: 0.33)
        case 70...:
            return Color(red: 0.78, green: 0.46, blue: 0.17)
        default:
            return Color(red: 0.68, green: 0.28, blue: 0.24)
        }
    }

    func scoreTintFill(for score: Int) -> Color {
        Self.scoreTint(for: score).opacity(colorScheme == .dark ? 0.2 : 0.12)
    }
}

enum AuraHaptics {
    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func impact(_ style: AuraHapticStyle = .light) {
        #if os(iOS)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: uiStyle = .light
        case .medium: uiStyle = .medium
        }
        UIImpactFeedbackGenerator(style: uiStyle).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func error() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

enum AuraHapticStyle {
    case light
    case medium
}

// MARK: - Streak Tracker

struct StreakTracker {
    private static let lastReadingDateKey = "aura.streak.lastReadingDate"
    private static let streakCountKey = "aura.streak.count"

    static func recordReading(date: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let stored = UserDefaults.standard.object(forKey: lastReadingDateKey) as? Date
        let lastDate = stored.map { calendar.startOfDay(for: $0) }

        if let lastDate {
            if calendar.isDate(lastDate, inSameDayAs: today) {
                return
            }

            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(lastDate, inSameDayAs: yesterday) {
                let current = UserDefaults.standard.integer(forKey: streakCountKey)
                UserDefaults.standard.set(current + 1, forKey: streakCountKey)
            } else {
                UserDefaults.standard.set(1, forKey: streakCountKey)
            }
        } else {
            UserDefaults.standard.set(1, forKey: streakCountKey)
        }

        UserDefaults.standard.set(today, forKey: lastReadingDateKey)
    }

    static var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let stored = UserDefaults.standard.object(forKey: lastReadingDateKey) as? Date else {
            return 0
        }

        let lastDate = calendar.startOfDay(for: stored)

        if calendar.isDate(lastDate, inSameDayAs: today) {
            return max(1, UserDefaults.standard.integer(forKey: streakCountKey))
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(lastDate, inSameDayAs: yesterday) {
            return max(1, UserDefaults.standard.integer(forKey: streakCountKey))
        }

        return 0
    }
}

// MARK: - Streak Notification Scheduler

struct StreakNotificationScheduler {
    private static let enabledKey = "aura.streakReminder.enabled"
    private static let hourKey = "aura.streakReminder.hour"
    private static let minuteKey = "aura.streakReminder.minute"
    private static let notificationID = "aura.streakReminder"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                scheduleIfNeeded()
            } else {
                cancel()
            }
        }
    }

    static var reminderHour: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: hourKey) as? Int
            return stored ?? 20
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hourKey)
            if isEnabled { scheduleIfNeeded() }
        }
    }

    static var reminderMinute: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: minuteKey) as? Int
            return stored ?? 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: minuteKey)
            if isEnabled { scheduleIfNeeded() }
        }
    }

    static var reminderTime: Date {
        get {
            var components = DateComponents()
            components.hour = reminderHour
            components.minute = reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 20
            reminderMinute = components.minute ?? 0
        }
    }

    #if os(iOS)
    static func requestPermissionAndEnable() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    isEnabled = true
                }
            }
        }
    }
    #endif

    static func rescheduleAfterReading() {
        guard isEnabled else { return }
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        #endif
    }

    static func scheduleIfNeeded() {
        #if os(iOS)
        guard isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let streak = StreakTracker.currentStreak

        let content = UNMutableNotificationContent()
        if streak > 0 {
            content.title = "Keep your \(streak)-day streak alive"
            content.body = "Open Aura for today's reading before the day ends."
        } else {
            content.title = "Start a new streak"
            content.body = "Open Aura for today's reading and build momentum."
        }
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = reminderHour
        dateComponents.minute = reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )
        center.add(request)
        #endif
    }

    static func cancel() {
        #if os(iOS)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
        #endif
    }

    // MARK: - Contextual Prompt

    private static let promptDismissedKey = "aura.streakReminder.promptDismissed"

    static var hasUserDismissedPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: promptDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptDismissedKey) }
    }

    static var shouldShowContextualPrompt: Bool {
        !isEnabled && !hasUserDismissedPrompt
    }
}

// MARK: - Retrograde Alert Scheduler

struct RetrogradeAlertScheduler {
    private static let enabledKey = "aura.retrogradeAlerts.enabled"
    private static let lastScheduledDateKey = "aura.retrogradeAlerts.lastScheduledDate"
    private static let notificationPrefix = "aura.retrogradeAlert."

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue {
                scheduleUpcomingAlerts()
            } else {
                cancelAll()
            }
        }
    }

    #if os(iOS)
    static func requestPermissionAndEnable() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    isEnabled = true
                }
            }
        }
    }
    #endif

    static func scheduleUpcomingAlerts() {
        #if os(iOS)
        guard isEnabled else { return }

        let center = UNUserNotificationCenter.current()

        // Remove existing retrograde alerts
        center.getPendingNotificationRequests { requests in
            let retroIDs = requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: retroIDs)
        }

        let now = Date()
        let calendar = Calendar.current

        for event in RetrogradeCatalog.events2026 {
            // Schedule alert 1 day before retrograde starts
            guard let alertDate = calendar.date(byAdding: .day, value: -1, to: event.startDate),
                  alertDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(event.symbol) \(event.planet) Retrograde Tomorrow"
            content.body = event.theme
            content.sound = .default

            var components = calendar.dateComponents([.year, .month, .day], from: alertDate)
            components.hour = 9
            components.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix)\(event.planet.lowercased()).\(components.year ?? 0).\(components.month ?? 0).\(components.day ?? 0)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }

        UserDefaults.standard.set(now, forKey: lastScheduledDateKey)
        #endif
    }

    static func cancelAll() {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let retroIDs = requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: retroIDs)
        }
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct AuraPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(for: configuration))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private func scale(for configuration: Configuration) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return configuration.isPressed ? 0.98 : 1
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct SkeletonShimmerModifier: ViewModifier {
    let active: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShimmerEnabled {
                    GeometryReader { proxy in
                        let gradientWidth = max(proxy.size.width * 0.42, 120)
                        let travelDistance = proxy.size.width + gradientWidth

                        LinearGradient(
                            colors: [.clear, shimmerHighlight, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: gradientWidth, height: proxy.size.height * 1.4)
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * travelDistance)
                        .allowsHitTesting(false)
                    }
                    .clipped()
                    .mask(content)
                }
            }
            .onAppear {
                refreshShimmerAnimation()
            }
            .onChange(of: isShimmerEnabled) { _, _ in
                refreshShimmerAnimation()
            }
    }

    private var shimmerHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.72)
    }

    private var isShimmerEnabled: Bool {
        active && !reduceMotion
    }

    private func refreshShimmerAnimation() {
        guard isShimmerEnabled else {
            phase = -1
            return
        }

        phase = -1
        withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension View {
    func skeletonShimmer(active: Bool) -> some View {
        modifier(SkeletonShimmerModifier(active: active))
    }
}
