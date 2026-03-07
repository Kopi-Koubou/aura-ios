import Foundation

struct RetrogradeEvent: Identifiable, Sendable {
    let id = UUID()
    let planet: String
    let symbol: String
    let startDate: Date
    let endDate: Date
    let theme: String

    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    func isUpcoming(withinDays days: Int = 3) -> Bool {
        let now = Date()
        guard now < startDate else { return false }
        let threshold = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return startDate <= threshold
    }

    var daysUntilStart: Int? {
        let now = Date()
        guard now < startDate else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: startDate).day
    }

    var daysRemaining: Int? {
        let now = Date()
        guard isActive else { return nil }
        return Calendar.current.dateComponents([.day], from: now, to: endDate).day
    }
}

enum RetrogradeCatalog {
    static var events2026: [RetrogradeEvent] {
        [
            // Mercury retrogrades (3-4x/year, ~3 weeks each)
            event("Mercury", symbol: "☿", start: "2026-01-26", end: "2026-02-16",
                  theme: "Communication slowdowns, travel delays"),
            event("Mercury", symbol: "☿", start: "2026-05-22", end: "2026-06-14",
                  theme: "Revisit plans, double-check agreements"),
            event("Mercury", symbol: "☿", start: "2026-09-17", end: "2026-10-09",
                  theme: "Tech glitches, misunderstandings"),

            // Venus retrograde (~every 18 months, ~40 days)
            event("Venus", symbol: "♀", start: "2026-03-02", end: "2026-04-12",
                  theme: "Relationship reflection, value reassessment"),

            // Mars retrograde (~every 2 years, ~2.5 months)
            event("Mars", symbol: "♂", start: "2026-12-07", end: "2027-02-24",
                  theme: "Low energy, revisit goals, avoid new conflicts"),

            // Jupiter retrograde (~4 months/year)
            event("Jupiter", symbol: "♃", start: "2026-07-12", end: "2026-11-08",
                  theme: "Inner growth, reassess ambitions"),

            // Saturn retrograde (~4.5 months/year)
            event("Saturn", symbol: "♄", start: "2026-06-08", end: "2026-10-23",
                  theme: "Review commitments, test boundaries"),

            // Uranus retrograde (~5 months/year)
            event("Uranus", symbol: "♅", start: "2026-09-06", end: "2027-02-03",
                  theme: "Reflect on change, pause disruptions"),

            // Neptune retrograde (~5.5 months/year)
            event("Neptune", symbol: "♆", start: "2026-07-04", end: "2026-12-10",
                  theme: "Clarity through disillusionment"),

            // Pluto retrograde (~5-6 months/year)
            event("Pluto", symbol: "♇", start: "2026-05-04", end: "2026-10-14",
                  theme: "Deep transformation, power dynamics"),
        ]
    }

    static var activeRetrogrades: [RetrogradeEvent] {
        events2026.filter { $0.isActive }
    }

    static var upcomingRetrogrades: [RetrogradeEvent] {
        events2026.filter { $0.isUpcoming(withinDays: 3) }
    }

    static var nextRetrograde: RetrogradeEvent? {
        let now = Date()
        return events2026
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
            .first
    }

    private static func event(_ planet: String, symbol: String, start: String, end: String, theme: String) -> RetrogradeEvent {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return RetrogradeEvent(
            planet: planet,
            symbol: symbol,
            startDate: formatter.date(from: start) ?? Date(),
            endDate: formatter.date(from: end) ?? Date(),
            theme: theme
        )
    }
}
