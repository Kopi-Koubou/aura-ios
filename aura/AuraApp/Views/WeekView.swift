import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct WeekView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false

    private let calendar = Calendar.current
    private let freePreviewDayCount = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard

                    if appState.currentUser == nil {
                        emptyState
                    } else {
                        weeklySummaryCard
                        outlookCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("This Week")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                await subscriptionManager.refreshStatus()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)

                Text(subscriptionManager.isPremium ? "7-Day Outlook" : "Weekly Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.accentFill())
            .clipShape(Capsule())

            Text("Your week at a glance")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)

            Text(weekRangeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(subscriptionManager.isPremium
                ? "Full seven-day rhythm tuned to your zodiac and MBTI profile."
                : "Preview your next three days. Unlock Premium for the full seven-day arc.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(accentColor.opacity(0.5))
                .frame(width: 64, height: 64)
                .background(theme.accentFill())
                .clipShape(Circle())

            VStack(spacing: 6) {
                Text("Profile Needed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Complete onboarding to unlock your weekly outlook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var weeklySummaryCard: some View {
        let days = weekDays

        if !days.isEmpty {
            let averageMetric = WeekSummaryMetric(
                title: "Average Energy",
                value: "\(averageEnergyScore(days: days))%",
                subtitle: "Across \(days.count) days",
                cardBackground: cardBackground,
                cardBorder: cardBorder
            )

            let focusMetric = WeekSummaryMetric(
                title: "Main Focus",
                value: dominantCategory(days: days).rawValue,
                subtitle: "Most recurring theme",
                cardBackground: cardBackground,
                cardBorder: cardBorder
            )

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        averageMetric
                        focusMetric
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            averageMetric
                            focusMetric
                        }

                        VStack(spacing: 12) {
                            averageMetric
                            focusMetric
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outlookCard: some View {
        let days = displayedDays

        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(subscriptionManager.isPremium ? "Daily Outlook" : "Daily Outlook Preview")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(days) { day in
                    WeekOutlookDayCard(
                        day: day,
                        isToday: calendar.isDateInToday(day.date),
                        accentColor: accentColor,
                        accentFill: theme.accentFill(),
                        accentBorder: theme.accentBorder(),
                        subtleFill: theme.subtleFill(),
                        cardBackground: cardBackground,
                        cardBorder: cardBorder,
                        calendar: calendar
                    )
                }

                if !subscriptionManager.isPremium {
                    WeekLockedCard(
                        remainingDays: max(0, weekDays.count - days.count),
                        accentColor: accentColor,
                        cardBackground: cardBackground,
                        cardBorder: cardBorder
                    ) {
                        presentPaywallFromUpsell()
                    }
                }
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        }
    }

    private var weekDays: [WeeklyOutlookDay] {
        guard let user = appState.currentUser else {
            return []
        }
        return WeeklyOutlookDay.generate(for: user, calendar: calendar)
    }

    private var displayedDays: [WeeklyOutlookDay] {
        guard !weekDays.isEmpty else {
            return []
        }

        if subscriptionManager.isPremium {
            return weekDays
        }

        return Array(weekDays.prefix(freePreviewDayCount))
    }

    private var weekRangeLabel: String {
        guard let start = weekStartDate,
              let end = calendar.date(byAdding: .day, value: 6, to: start)
        else {
            return "This week"
        }

        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(format)) - \(end.formatted(format))"
    }

    private var weekStartDate: Date? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return nil
        }
        return calendar.startOfDay(for: interval.start)
    }

    private func averageEnergyScore(days: [WeeklyOutlookDay]) -> Int {
        guard !days.isEmpty else {
            return 0
        }

        let total = days.reduce(0) { partial, day in
            partial + day.energyScore
        }
        return Int(Double(total) / Double(days.count))
    }

    private func dominantCategory(days: [WeeklyOutlookDay]) -> SituationCategory {
        let grouped = Dictionary(grouping: days, by: { $0.focusCategory })
        return grouped.max { lhs, rhs in
            lhs.value.count < rhs.value.count
        }?.key ?? .career
    }

    private func presentPaywallFromUpsell() {
        triggerImpactFeedback()
        showPaywall = true
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var backgroundColor: Color { theme.background }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private func triggerImpactFeedback() { AuraHaptics.impact() }
}

@available(iOS 17.0, macOS 14.0, *)
private struct WeeklyOutlookDay: Identifiable {
    let id: Date
    let date: Date
    let focusCategory: SituationCategory
    let energyScore: Int
    let reflection: String

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func generate(for user: UserProfile, calendar: Calendar) -> [WeeklyOutlookDay] {
        let start: Date

        if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) {
            start = calendar.startOfDay(for: weekInterval.start)
        } else {
            start = calendar.startOfDay(for: Date())
        }

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            let dayKey = dayFormatter.string(from: date)
            let seed = "\(user.id.uuidString)|\(user.zodiacSign.rawValue)|\(user.mbtiType.rawValue)|week|\(dayKey)"
            var generator = SeededRandomGenerator(seed: seed)

            let energyScore = generator.randomInt(in: 58...95)
            let categoryIndex = generator.randomInt(in: 0...(SituationCategory.allCases.count - 1))
            let category = SituationCategory.allCases[categoryIndex]
            let reflection = reflectionText(
                energyScore: energyScore,
                category: category,
                zodiac: user.zodiacSign,
                mbtiType: user.mbtiType,
                generator: &generator
            )

            return WeeklyOutlookDay(
                id: date,
                date: date,
                focusCategory: category,
                energyScore: energyScore,
                reflection: reflection
            )
        }
    }

    private static func reflectionText(
        energyScore: Int,
        category: SituationCategory,
        zodiac: ZodiacSign,
        mbtiType: MBTIType,
        generator: inout SeededRandomGenerator
    ) -> String {
        let cat = category.rawValue.lowercased()
        let trait = zodiacTrait(zodiac)
        let style = mbtiStyle(mbtiType)

        let templates: [String]

        if energyScore >= 84 {
            templates = [
                "Strong momentum for \(cat). Your \(trait) gives you an edge — lean in early.",
                "Peak energy aligns with \(cat) today. Channel your \(style) and make the bold move.",
                "The stars favor \(cat). Trust your \(trait) — this is a day to act, not deliberate.",
                "High-voltage \(cat) day. Your \(style) thrives here — lead with confidence.",
            ]
        } else if energyScore >= 70 {
            templates = [
                "Steady conditions for \(cat). Let your \(trait) guide one clear priority today.",
                "Solid ground in \(cat). Your \(style) keeps you on course — pick one thing and finish it.",
                "Balanced energy for \(cat). Lean on your \(trait) to stay focused without overcommitting.",
                "A reliable rhythm for \(cat). Your \(style) works best with one intentional step forward.",
            ]
        } else {
            templates = [
                "Keep \(cat) lighter today. Your \(trait) benefits from a slower pace — protect your reserves.",
                "A quieter \(cat) day. Use your \(style) to recharge rather than push through.",
                "Ease up on \(cat). Your \(trait) renews best when you give it breathing room.",
                "Low-pressure \(cat) window. Let your \(style) guide you toward rest over hustle.",
            ]
        }

        let index = generator.randomInt(in: 0...(templates.count - 1))
        return templates[index]
    }

    private static func zodiacTrait(_ sign: ZodiacSign) -> String {
        switch sign {
        case .aries:       return "fire-starter instinct"
        case .taurus:      return "grounded patience"
        case .gemini:      return "quick adaptability"
        case .cancer:      return "emotional intuition"
        case .leo:         return "natural magnetism"
        case .virgo:       return "meticulous clarity"
        case .libra:       return "diplomatic sense"
        case .scorpio:     return "deep intensity"
        case .sagittarius: return "adventurous drive"
        case .capricorn:   return "disciplined ambition"
        case .aquarius:    return "visionary thinking"
        case .pisces:      return "creative empathy"
        }
    }

    private static func mbtiStyle(_ type: MBTIType) -> String {
        switch type {
        case .INTJ: return "strategic mind"
        case .INTP: return "analytical lens"
        case .ENTJ: return "decisive leadership"
        case .ENTP: return "inventive spark"
        case .INFJ: return "quiet conviction"
        case .INFP: return "idealist compass"
        case .ENFJ: return "empathetic leadership"
        case .ENFP: return "enthusiastic vision"
        case .ISTJ: return "methodical focus"
        case .ISFJ: return "steady care"
        case .ESTJ: return "structured drive"
        case .ESFJ: return "community instinct"
        case .ISTP: return "hands-on logic"
        case .ISFP: return "artistic sensitivity"
        case .ESTP: return "bold pragmatism"
        case .ESFP: return "spontaneous energy"
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct WeekSummaryMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let cardBackground: Color
    let cardBorder: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct WeekOutlookDayCard: View {
    let day: WeeklyOutlookDay
    let isToday: Bool
    let accentColor: Color
    let accentFill: Color
    let accentBorder: Color
    let subtleFill: Color
    let cardBackground: Color
    let cardBorder: Color
    let calendar: Calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayHeader

            EnergyBar(energyScore: day.energyScore)

            Text(day.reflection)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(isToday ? subtleFill : cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? accentBorder : cardBorder, lineWidth: isToday ? 1.5 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(dayTitle). \(day.focusCategory.rawValue) focus. Energy \(day.energyScore) percent. \(day.reflection)")
    }

    @ViewBuilder
    private var dayHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                dayMeta
                focusPill
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    dayMeta

                    Spacer(minLength: 8)

                    focusPill
                }

                VStack(alignment: .leading, spacing: 8) {
                    dayMeta
                    focusPill
                }
            }
        }
    }

    private var dayMeta: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(dayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if isToday {
                    Text("NOW")
                        .font(.caption2.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(accentFill)
                        .clipShape(Capsule())
                }
            }

            Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var focusPill: some View {
        Label(day.focusCategory.rawValue, systemImage: day.focusCategory.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(accentFill)
            .clipShape(Capsule())
    }

    private var dayTitle: String {
        if calendar.isDateInToday(day.date) {
            return "Today"
        }

        if calendar.isDateInTomorrow(day.date) {
            return "Tomorrow"
        }

        return day.date.formatted(.dateTime.weekday(.wide))
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct EnergyBar: View {
    let energyScore: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Energy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(energyScore)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AuraTheme(colorScheme: colorScheme).iconFill)

                    Capsule()
                        .fill(tintColor)
                        .frame(width: max(12, geometry.size.width * CGFloat(energyScore) / 100))
                }
            }
            .frame(height: 8)
        }
    }

    private var tintColor: Color {
        AuraTheme.scoreTint(for: energyScore)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct WeekLockedCard: View {
    let remainingDays: Int
    let accentColor: Color
    let cardBackground: Color
    let cardBorder: Color
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)

                Text("Premium Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            Text("Unlock \(remainingDays) more days")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Get the full seven-day rhythm with complete category coverage and deeper guidance.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUpgrade) {
                Text("View Premium")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(AuraPressButtonStyle())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }
}
