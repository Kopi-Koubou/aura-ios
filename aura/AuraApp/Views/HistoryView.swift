import SwiftUI
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if subscriptionManager.isPremium {
                    premiumHistoryContent
                } else {
                    freeGateContent
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("History")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Premium History

    private var premiumHistoryContent: some View {
        HistoryListView()
            .environment(appState)
    }

    // MARK: - Free Gate

    private var freeGateContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(theme.mutedIcon)

            VStack(spacing: 8) {
                Text("Your Reading Journal")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Revisit past readings and track how guidance unfolds over time. Available with Premium.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }

            Button {
                AuraHaptics.impact()
                showPaywall = true
            } label: {
                Text("Unlock History")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 240)
                    .frame(height: 48)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(AuraPressButtonStyle())
            .frame(minHeight: 44)
            .contentShape(Rectangle())

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading history is a premium feature")
        .accessibilityHint("Double tap to view premium options")
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }
    private var accentColor: Color { theme.accent }
    private var backgroundColor: Color { theme.background }
}

// MARK: - History List (premium only)

@available(iOS 17.0, macOS 14.0, *)
private struct HistoryListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @State private var readings: [DailyReading] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if readings.isEmpty && hasLoaded {
                emptyState
            } else if readings.isEmpty {
                skeletonPlaceholder
            } else {
                readingList
            }
        }
        .task {
            await loadReadings()
        }
        .refreshable {
            await loadReadings()
        }
    }

    private var readingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groupedByDate, id: \.key) { dateKey, dayReadings in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(dateKey)
                            .font(.caption.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(dayReadings, id: \.id) { reading in
                                HistoryRow(reading: reading)
                                    .padding(.horizontal, 16)

                                if reading.id != dayReadings.last?.id {
                                    Divider()
                                        .padding(.leading, 64)
                                        .padding(.trailing, 16)
                                }
                            }
                        }
                        .background(theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.cardBorder, lineWidth: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.book.closed")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(theme.mutedIcon)

            VStack(spacing: 8) {
                Text("No readings yet")
                    .font(.system(.body, design: .serif).weight(.medium))
                    .foregroundStyle(.primary)

                Text("Your daily readings will appear here as you explore each category.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No readings yet. Your daily readings will appear here.")
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var skeletonPlaceholder: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(theme.fieldBackground)
                                    .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(theme.fieldBackground)
                                        .frame(width: 90, height: 14)
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(theme.fieldBackground)
                                        .frame(width: 50, height: 10)
                                }

                                Spacer()

                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.fieldBackground)
                                    .frame(width: 36, height: 22)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if row == 0 {
                                Divider()
                                    .padding(.leading, 64)
                                    .padding(.trailing, 16)
                            }
                        }
                    }
                    .background(theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.cardBorder, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28)
            .skeletonShimmer(active: true)
        }
    }

    private var groupedByDate: [(key: String, value: [DailyReading])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = .current

        let grouped = Dictionary(grouping: readings) { reading -> String in
            let startOfDay = calendar.startOfDay(for: reading.date)
            let today = calendar.startOfDay(for: Date())

            if calendar.isDate(startOfDay, inSameDayAs: today) {
                return "TODAY"
            }

            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(startOfDay, inSameDayAs: yesterday) {
                return "YESTERDAY"
            }

            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: reading.date).uppercased()
        }

        return grouped
            .sorted { pair1, pair2 in
                let date1 = pair1.value.first?.date ?? .distantPast
                let date2 = pair2.value.first?.date ?? .distantPast
                return date1 > date2
            }
    }

    @MainActor
    private func loadReadings() async {
        guard let user = appState.currentUser else {
            hasLoaded = true
            return
        }

        let userID = user.id
        let descriptor = FetchDescriptor<DailyReading>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            let allReadings = try modelContext.fetch(descriptor)
            readings = allReadings.filter { $0.user?.id == userID }
        } catch {
            readings = []
        }

        hasLoaded = true
        AnalyticsService.shared.track(.historyViewed)
    }
}

// MARK: - History Row

@available(iOS 17.0, macOS 14.0, *)
private struct HistoryRow: View {
    let reading: DailyReading

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                AuraHaptics.selection()
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    categoryIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.category.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text(reading.date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    fortuneScoreBadge

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("\(reading.category.rawValue) reading, fortune score \(reading.fortuneScore)")
            .accessibilityHint(isExpanded ? "Collapse reading" : "Expand reading")

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Text(reading.content)
                        .font(.subheadline)
                        .lineSpacing(2)
                        .foregroundStyle(.primary)

                    fortuneBar

                    historyMantra

                    if !reading.luckyNumbers.isEmpty || !reading.powerColors.isEmpty {
                        expandedExtras
                    }
                }
                .padding(.leading, 48)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var fortuneBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("FORTUNE")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(reading.fortuneScore)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AuraTheme.scoreTint(for: reading.fortuneScore))
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.fieldBackground)
                        .frame(height: 6)

                    Capsule()
                        .fill(AuraTheme.scoreTint(for: reading.fortuneScore))
                        .frame(width: max(6, geo.size.width * CGFloat(reading.fortuneScore) / 100), height: 6)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fortune score \(reading.fortuneScore) percent")
    }

    private var historyMantra: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("INTENTION")
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Text(reading.dailyMantra())
                .font(.system(.caption, design: .serif))
                .italic()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily intention: \(reading.dailyMantra())")
    }

    private var expandedExtras: some View {
        HStack(alignment: .top, spacing: 16) {
            if !reading.luckyNumbers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LUCKY NUMBERS")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    Text(reading.luckyNumbers.map(String.init).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 8)

            if !reading.powerColors.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("POWER COLORS")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    Text(reading.powerColors.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var categoryIcon: some View {
        Image(systemName: reading.category.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.accent)
            .frame(width: 36, height: 36)
            .background(theme.accentFill())
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fortuneScoreBadge: some View {
        Text("\(reading.fortuneScore)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(AuraTheme.scoreTint(for: reading.fortuneScore))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.scoreTintFill(for: reading.fortuneScore))
            .clipShape(Capsule())
            .accessibilityLabel("Fortune score \(reading.fortuneScore)")
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }
}
