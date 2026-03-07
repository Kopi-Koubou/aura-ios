import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedCategory: SituationCategory = .career
    @State private var currentReading: DailyReading?
    @State private var loadState = TodayReadingLoadState()
    @State private var readingError: AppError?
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var shareState = TodaySharePresentationState()
    @State private var retryCooldownRemainingSeconds = 0
    @State private var retryCooldownTask: Task<Void, Never>?
    @State private var automaticRecoveryAttemptCount = 0
    @State private var readingStreak = StreakTracker.currentStreak
    @State private var showStreakReminderPrompt = StreakNotificationScheduler.shouldShowContextualPrompt

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greetingHeader
                    CategorySelector(selectedCategory: $selectedCategory)
                    loadErrorBanner

                    if let reading = visibleReading {
                        refreshStatusBanner
                        ReadingCard(reading: reading)
                        premiumUpsellBanner(reading: reading)
                        FortuneCard(reading: reading)
                        retrogradeAlertCard
                        streakReminderPromptCard
                        shareButton(reading: reading)
                    } else if presentationState.showsLoadingSkeleton {
                        TodayLoadingSkeleton(cardBackground: cardBackground, cardBorder: cardBorder)
                            .padding(.top, 4)
                    } else if let fallbackState = temporaryGuidanceState {
                        temporaryGuidanceCard(state: fallbackState)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    } else {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Today")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .refreshable {
                await refreshReading()
            }
            .task(id: selectedCategory) {
                shareState.clearFailure()
                switch automaticLoadPolicy.categoryLoadBehavior {
                case .fullLoad:
                    await loadReading(for: selectedCategory)
                case .cacheOnly:
                    loadCachedReadingIfAvailable(for: selectedCategory)
                }
            }
            .onDisappear {
                clearRetryCooldown()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            #if os(iOS)
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(items: shareItems)
            }
            #endif
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        let headerState = greetingHeaderState

        return Group {
            if headerState.usesStackedLayout {
                VStack(alignment: .leading, spacing: 12) {
                    greetingTextBlock

                    if headerState.showsPremiumButton {
                        premiumEntryButton
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    greetingTextBlock

                    Spacer(minLength: 12)

                    if headerState.showsPremiumButton {
                        premiumEntryButton
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    private var greetingTextBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.system(.title2, design: .serif).weight(.semibold))

            if let user = appState.currentUser {
                HStack(spacing: 8) {
                    Text("\(user.zodiacSign.symbol) \(user.zodiacSign.rawValue.capitalized) - \(user.mbtiType.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if readingStreak > 0 {
                        streakBadge
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.caption2.weight(.bold))
            Text("\(readingStreak)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(streakTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(theme.tintFill(for: streakTint))
        .clipShape(Capsule())
        .accessibilityLabel("\(readingStreak) day reading streak")
    }

    private var streakTint: Color {
        theme.streakTint(for: readingStreak)
    }

    private var premiumEntryButton: some View {
        Button {
            triggerImpactFeedback()
            showPaywall = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.semibold))
                Text("Premium")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, actionLayoutState.compactPillVerticalPadding)
            .frame(minHeight: actionLayoutState.compactPillMinHeight)
            .background(theme.accentFill())
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.accentBorder(), lineWidth: 1)
            }
        }
        .buttonStyle(AuraPressButtonStyle())
    }

    // MARK: - Retrograde Alert

    @ViewBuilder
    private var retrogradeAlertCard: some View {
        if subscriptionManager.isPremium {
            let active = RetrogradeCatalog.activeRetrogrades
            let upcoming = RetrogradeCatalog.upcomingRetrogrades

            if !active.isEmpty || !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(retrogradeIconColor)
                            .frame(width: 28, height: 28)
                            .background(theme.tintFill(for: retrogradeIconColor))
                            .clipShape(Circle())

                        Text(active.isEmpty ? "Retrograde Incoming" : "Retrograde Active")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        if !active.isEmpty {
                            Text("\(active.count) planet\(active.count == 1 ? "" : "s")")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ForEach(active) { event in
                        retrogradeRow(event: event, isActive: true)
                    }
                    ForEach(upcoming) { event in
                        retrogradeRow(event: event, isActive: false)
                    }

                    if !RetrogradeAlertScheduler.isEnabled {
                        Button {
                            triggerImpactFeedback()
                            #if os(iOS)
                            RetrogradeAlertScheduler.requestPermissionAndEnable()
                            #endif
                            AnalyticsService.shared.track(.retrogradeAlertEnabled)
                        } label: {
                            Label("Enable retrograde alerts", systemImage: "bell")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(theme.accentFill())
                                .clipShape(Capsule())
                        }
                        .buttonStyle(AuraPressButtonStyle())
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
                .onAppear {
                    AnalyticsService.shared.track(.retrogradeAlertViewed, properties: [
                        "active_count": active.count,
                        "upcoming_count": upcoming.count,
                    ])
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Planetary retrograde status")
            }
        }
    }

    private func retrogradeRow(event: RetrogradeEvent, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Text(event.symbol)
                .font(.system(size: 16))
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.planet)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    if isActive, let days = event.daysRemaining {
                        Text("\(days)d left")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(retrogradeIconColor)
                    } else if let days = event.daysUntilStart {
                        Text("in \(days)d")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(event.theme)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var retrogradeIconColor: Color { AuraTheme.retrogradeAmber }

    // MARK: - Streak Reminder Prompt

    @ViewBuilder
    private var streakReminderPromptCard: some View {
        if showStreakReminderPrompt {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 28, height: 28)
                        .background(theme.accentFill())
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily reminder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("A gentle nudge each evening to keep your streak going.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        enableStreakReminder()
                    } label: {
                        Text("Enable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(AuraPressButtonStyle())

                    Button {
                        dismissStreakReminderPrompt()
                    } label: {
                        Text("Not Now")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(cardBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(AuraPressButtonStyle())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .onAppear {
                AnalyticsService.shared.track(.streakReminderPromptShown)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Daily streak reminder")
            .accessibilityHint("Enable a daily notification to remind you to read your horoscope.")
        }
    }

    private func enableStreakReminder() {
        triggerImpactFeedback()
        #if os(iOS)
        StreakNotificationScheduler.requestPermissionAndEnable()
        #endif
        AnalyticsService.shared.track(.streakReminderEnabled)

        if reduceMotion {
            showStreakReminderPrompt = false
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                showStreakReminderPrompt = false
            }
        }
    }

    private func dismissStreakReminderPrompt() {
        triggerSelectionFeedback()
        StreakNotificationScheduler.hasUserDismissedPrompt = true
        AnalyticsService.shared.track(.streakReminderPromptDismissed)

        if reduceMotion {
            showStreakReminderPrompt = false
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                showStreakReminderPrompt = false
            }
        }
    }

    // MARK: - Premium Upsell

    @ViewBuilder
    private func premiumUpsellBanner(reading: DailyReading) -> some View {
        if !subscriptionManager.isPremium && !reading.isPremium {
            Button {
                triggerImpactFeedback()
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get the Full Reading")
                            .font(.subheadline.weight(.semibold))
                        Text("Unlock deeper daily guidance with Premium.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(AuraPressButtonStyle())
        }
    }

    // MARK: - Share

    @ViewBuilder
    private func shareButton(reading: DailyReading) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                triggerSelectionFeedback()
                Task {
                    await prepareShare(for: reading)
                }
            } label: {
                HStack(spacing: 8) {
                    if shareState.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(shareState.buttonTitle)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, actionLayoutState.primaryButtonVerticalPadding)
                .frame(minHeight: actionLayoutState.primaryButtonMinHeight)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(AuraPressButtonStyle())
            .disabled(shareState.isPreparing)
            .accessibilityHint(shareState.buttonAccessibilityHint)

            if let failureMessage = shareState.failureMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(errorTint)
                        .padding(.top, 1)

                    Text(failureMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
            }
        }
        #else
        let service = ShareService()
        if let text = service.shareText(for: reading) {
            ShareLink(
                item: service.deepLink(for: reading),
                subject: Text("My Aura Reading"),
                message: Text(text)
            ) {
                Label("Share Reading", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, actionLayoutState.primaryButtonVerticalPadding)
                    .frame(minHeight: actionLayoutState.primaryButtonMinHeight)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(AuraPressButtonStyle())
        } else {
            EmptyView()
        }
        #endif
    }

    @MainActor
    private func prepareShare(for reading: DailyReading) async {
        guard !shareState.isPreparing else { return }

        shareState.beginPreparing()
        let service = ShareService()
        let preparedItems = await service.shareItems(for: reading, colorScheme: colorScheme)

        shareItems = preparedItems
        shareState.finish(preparedItemCount: preparedItems.count)

        if !preparedItems.isEmpty {
            AnalyticsService.shared.track(.shareInitiated, properties: [
                "category": reading.category.rawValue,
            ])
            showShareSheet = true
        } else {
            triggerWarningFeedback()
        }
    }

    // MARK: - Empty + Loading

    @ViewBuilder
    private var loadErrorBanner: some View {
        if let readingError, !showsTemporaryGuidanceFallback {
            let bannerState = TodayLoadErrorBannerPresentationState(
                readingError: readingError,
                hasVisibleReading: visibleReading != nil,
                isCoolingDown: retryActionState.isCoolingDown,
                cooldownRemainingSeconds: retryCooldownRemainingSeconds,
                visibleReadingCreatedAt: visibleReading?.createdAt
            )
            let bannerTint = bannerTint(for: bannerState.tone)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: bannerState.iconSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bannerTint)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bannerState.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(bannerState.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let recencyLabel = bannerState.savedGuidanceRecencyLabel {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.caption.weight(.semibold))
                            Text(recencyLabel)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 8)

                Button {
                    retryReading()
                } label: {
                    Text(retryActionState.bannerButtonTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bannerTint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, actionLayoutState.bannerButtonVerticalPadding)
                        .frame(minHeight: actionLayoutState.bannerButtonMinHeight)
                        .background(theme.tintFill(for: bannerTint))
                        .clipShape(Capsule())
                }
                .buttonStyle(AuraPressButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .disabled(retryActionState.isDisabled)
                .accessibilityHint(retryActionState.bannerAccessibilityHint)
            }
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityValue(bannerState.accessibilityValue)
        }
    }

    private func temporaryGuidanceCard(state: TodayTemporaryGuidanceState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                Text("Temporary Guidance")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, actionLayoutState.compactPillVerticalPadding)
            .frame(minHeight: actionLayoutState.compactPillMinHeight)
            .background(theme.accentFill())
            .clipShape(Capsule())

            Text(state.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(state.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.bodyText)
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Today's quick signals")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("Fortune pulse: \(state.fortuneScore)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Lucky numbers: \(state.luckyNumbersText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Power colors: \(state.powerColorsText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Today's quick signals. Fortune pulse \(state.fortuneScore) percent. Lucky numbers \(state.luckyNumbersAccessibilityText). Power colors \(state.powerColorsAccessibilityText)."
            )

            Button {
                retryReading()
            } label: {
                HStack(spacing: 8) {
                    if retryActionState.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: retryActionState.cardButtonSymbol)
                    }

                    Text(retryActionState.cardButtonTitle)
                        .lineLimit(actionLayoutState.retryButtonLineLimit)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: actionLayoutState.usesAccessibilityLayout)
                        .minimumScaleFactor(actionLayoutState.retryButtonMinimumScaleFactor)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, actionLayoutState.primaryButtonVerticalPadding)
                .frame(minHeight: actionLayoutState.primaryButtonMinHeight)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(AuraPressButtonStyle())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(retryActionState.isDisabled)
            .accessibilityHint(retryActionState.cardAccessibilityHint)

            if retryActionState.isCoolingDown {
                VStack(alignment: .leading, spacing: 10) {
                    cooldownStatusHeader

                    TodayCooldownProgressBar(
                        progress: retryActionState.cooldownProgress,
                        trackColor: cardBorder.opacity(colorScheme == .dark ? 0.9 : 0.7), // unique track opacity, not a fill pattern
                        fillColor: accentColor
                    )
                    .accessibilityHidden(true)

                    if let autoRecoveryMessage = automaticRecoveryStatusMessage {
                        Label(autoRecoveryMessage, systemImage: automaticRecoveryStatusSymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Live guidance cooldown")
                .accessibilityValue(
                    retryActionState.cooldownAccessibilitySummary(
                        autoRecoveryMessage: automaticRecoveryStatusMessage
                    )
                )
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

    @ViewBuilder
    private var refreshStatusBanner: some View {
        if presentationState.showsRefreshIndicator {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Updating today's guidance")
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, actionLayoutState.statusBannerVerticalPadding)
            .frame(minHeight: actionLayoutState.statusBannerMinHeight)
            .background(cardBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Refreshing today's reading")
        }
    }

    @ViewBuilder
    private var cooldownStatusHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(retryActionState.cooldownMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                cooldownTimerBadge
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(retryActionState.cooldownMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)
                cooldownTimerBadge
            }
        }
    }

    private var cooldownTimerBadge: some View {
        Text(retryActionState.cooldownTimerLabel)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(cardBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .contentTransition(reduceMotion ? .identity : .numericText())
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(accentColor.opacity(0.5))
                .frame(width: 64, height: 64)
                .background(theme.subtleFill())
                .clipShape(Circle())

            VStack(spacing: 6) {
                Text("No Reading Yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Your daily horoscope appears here once a category is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                triggerSelectionFeedback()
                Task { await loadReading(for: selectedCategory) }
            } label: {
                Text("Refresh")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(theme.accentFill())
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(AuraPressButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadReading(for category: SituationCategory) async {
        guard let user = appState.currentUser else { return }
        guard let contentService = appState.contentService else { return }

        readingError = nil
        let requestID = loadState.begin()
        defer { loadState.finish(requestID) }

        do {
            let reading = try await contentService.todayReading(for: user, category: category)
            guard loadState.shouldApply(
                requestID,
                completedCategory: category,
                selectedCategory: selectedCategory,
                isCancelled: Task.isCancelled
            ) else { return }
            currentReading = reading
            readingError = nil
            clearRetryCooldown()
            automaticRecoveryAttemptCount = 0
            StreakTracker.recordReading()
            StreakNotificationScheduler.rescheduleAfterReading()
            let updatedStreak = StreakTracker.currentStreak
            if updatedStreak != readingStreak {
                readingStreak = updatedStreak
                if [3, 7, 14, 30, 60, 100].contains(updatedStreak) {
                    AuraHaptics.success()
                    AnalyticsService.shared.track(.streakMilestone, properties: [
                        "streak_days": updatedStreak,
                    ])
                }
            }
            AnalyticsService.shared.track(.readingViewed, properties: [
                "category": category.rawValue,
                "is_premium": subscriptionManager.isPremium,
            ])
        } catch is CancellationError {
            return
        } catch {
            guard loadState.shouldApply(
                requestID,
                completedCategory: category,
                selectedCategory: selectedCategory,
                isCancelled: Task.isCancelled
            ) else { return }
            let mappedError = AppError.fromReadingLoadError(error)
            readingError = mappedError
            if case .contentNotAvailable = mappedError {
                scheduleRetryCooldown()
            } else {
                clearRetryCooldown()
                automaticRecoveryAttemptCount = 0
            }
        }
    }

    private func loadCachedReadingIfAvailable(for category: SituationCategory) {
        guard let user = appState.currentUser else { return }
        guard let contentService = appState.contentService else { return }

        do {
            guard
                let cachedReading = try contentService.cachedTodayReading(
                    for: user,
                    category: category
                )
            else {
                return
            }

            guard category == selectedCategory else {
                return
            }

            currentReading = cachedReading
        } catch {
            // Keep the current fallback state if the cache lookup fails.
        }
    }

    private var presentationState: TodayReadingPresentationState {
        TodayReadingPresentationState(
            selectedCategory: selectedCategory,
            currentReadingCategory: currentReading?.category,
            isLoading: loadState.isLoading
        )
    }

    private var visibleReading: DailyReading? {
        guard currentReading?.category == selectedCategory else {
            return nil
        }
        return currentReading
    }

    private var temporaryGuidancePresentationState: TodayTemporaryGuidancePresentationState {
        TodayTemporaryGuidancePresentationState(
            hasUser: appState.currentUser != nil,
            isLoading: loadState.isLoading,
            hasVisibleReading: visibleReading != nil,
            readingError: readingError
        )
    }

    private var showsTemporaryGuidanceFallback: Bool {
        temporaryGuidancePresentationState.shouldShowTemporaryGuidance
    }

    private var temporaryGuidanceState: TodayTemporaryGuidanceState? {
        guard showsTemporaryGuidanceFallback else {
            return nil
        }

        guard let user = appState.currentUser else {
            return nil
        }

        return TodayTemporaryGuidanceState(
            userID: user.id,
            zodiacSign: user.zodiacSign,
            mbtiType: user.mbtiType,
            category: selectedCategory,
            date: Date()
        )
    }

    private var retryActionState: TodayRetryActionState {
        TodayRetryActionState(
            isLoading: loadState.isLoading,
            cooldownRemainingSeconds: retryCooldownRemainingSeconds
        )
    }

    private var automaticLoadPolicy: TodayAutomaticLoadPolicy {
        TodayAutomaticLoadPolicy(
            isCoolingDown: retryActionState.isCoolingDown,
            readingError: readingError
        )
    }

    private var automaticRecoveryPolicy: TodayAutomaticRecoveryPolicy {
        TodayAutomaticRecoveryPolicy(
            isLoading: loadState.isLoading,
            readingError: readingError,
            hasVisibleReading: visibleReading != nil,
            automaticRecoveryAttempts: automaticRecoveryAttemptCount
        )
    }

    private var automaticRecoveryStatusMessage: String? {
        guard retryActionState.isCoolingDown else {
            return nil
        }

        return automaticRecoveryPolicy.cooldownStatusMessage
    }

    private var automaticRecoveryStatusSymbol: String {
        automaticRecoveryPolicy.cooldownStatusSymbol ?? "clock.badge.exclamationmark"
    }

    private var greetingHeaderState: TodayGreetingHeaderPresentationState {
        TodayGreetingHeaderPresentationState(
            dynamicTypeSize: dynamicTypeSize,
            isPremium: subscriptionManager.isPremium
        )
    }

    private var actionLayoutState: TodayActionLayoutState {
        TodayActionLayoutState(dynamicTypeSize: dynamicTypeSize)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5..<12: timeGreeting = "Good Morning"
        case 12..<17: timeGreeting = "Good Afternoon"
        default: timeGreeting = "Good Evening"
        }
        if let name = appState.currentUser?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(timeGreeting), \(name)"
        }
        return timeGreeting
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var errorTint: Color { theme.errorTint }

    private var backgroundColor: Color { theme.background }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private func bannerTint(for tone: TodayLoadErrorBannerTone) -> Color {
        switch tone {
        case .informational:
            return accentColor
        case .critical:
            return errorTint
        }
    }

    private func triggerSelectionFeedback() { AuraHaptics.selection() }

    private func retryReading() {
        guard !retryActionState.isDisabled else {
            return
        }

        triggerSelectionFeedback()
        Task { await loadReading(for: selectedCategory) }
    }

    private func refreshReading() async {
        // Ignore pull-to-refresh while a request is already active to avoid duplicate generation.
        guard !loadState.isLoading else {
            return
        }

        guard retryActionState.allowsManualRefresh else {
            triggerWarningFeedback()
            return
        }

        await loadReading(for: selectedCategory)
    }

    private func scheduleRetryCooldown() {
        retryCooldownTask?.cancel()
        retryCooldownRemainingSeconds = TodayRetryActionState.cooldownDurationSeconds

        retryCooldownTask = Task {
            var remainingSeconds = TodayRetryActionState.cooldownDurationSeconds
            while remainingSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remainingSeconds -= 1

                await MainActor.run {
                    if reduceMotion {
                        retryCooldownRemainingSeconds = remainingSeconds
                    } else {
                        withAnimation(.easeOut(duration: 0.22)) {
                            retryCooldownRemainingSeconds = remainingSeconds
                        }
                    }
                }
            }

            await MainActor.run {
                retryCooldownTask = nil
                triggerAutomaticRecoveryAfterCooldownIfNeeded()
            }
        }
    }

    private func clearRetryCooldown() {
        retryCooldownTask?.cancel()
        retryCooldownTask = nil
        retryCooldownRemainingSeconds = 0
    }

    private func triggerAutomaticRecoveryAfterCooldownIfNeeded() {
        guard automaticRecoveryPolicy.shouldAttemptAutomaticRecovery else {
            return
        }

        automaticRecoveryAttemptCount += 1

        Task {
            await loadReading(for: selectedCategory)
        }
    }

    private func triggerImpactFeedback() { AuraHaptics.impact() }

    private func triggerWarningFeedback() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayReadingLoadState: Sendable {
    private(set) var isLoading = false
    private(set) var activeRequestID: UUID?

    mutating func begin() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        return requestID
    }

    mutating func finish(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        isLoading = false
    }

    func shouldApply(
        _ requestID: UUID,
        completedCategory: SituationCategory,
        selectedCategory: SituationCategory,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && activeRequestID == requestID
            && completedCategory == selectedCategory
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayReadingPresentationState: Sendable {
    let selectedCategory: SituationCategory
    let currentReadingCategory: SituationCategory?
    let isLoading: Bool

    var selectedReadingIsVisible: Bool {
        currentReadingCategory == selectedCategory
    }

    var showsLoadingSkeleton: Bool {
        isLoading && !selectedReadingIsVisible
    }

    var showsRefreshIndicator: Bool {
        isLoading && selectedReadingIsVisible
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayGreetingHeaderPresentationState: Sendable {
    let dynamicTypeSize: DynamicTypeSize
    let isPremium: Bool

    var showsPremiumButton: Bool {
        !isPremium
    }

    var usesStackedLayout: Bool {
        dynamicTypeSize.isAccessibilitySize && showsPremiumButton
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayActionLayoutState: Sendable {
    let dynamicTypeSize: DynamicTypeSize

    var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var primaryButtonMinHeight: CGFloat {
        usesAccessibilityLayout ? 56 : 48
    }

    var primaryButtonVerticalPadding: CGFloat {
        usesAccessibilityLayout ? 4 : 0
    }

    var statusBannerMinHeight: CGFloat {
        usesAccessibilityLayout ? 40 : 32
    }

    var statusBannerVerticalPadding: CGFloat {
        usesAccessibilityLayout ? 2 : 0
    }

    var compactPillMinHeight: CGFloat {
        usesAccessibilityLayout ? 34 : 28
    }

    var compactPillVerticalPadding: CGFloat {
        usesAccessibilityLayout ? 1 : 0
    }

    var bannerButtonMinHeight: CGFloat {
        usesAccessibilityLayout ? 36 : 30
    }

    var bannerButtonVerticalPadding: CGFloat {
        usesAccessibilityLayout ? 1 : 0
    }

    var retryButtonLineLimit: Int? {
        usesAccessibilityLayout ? nil : 1
    }

    var retryButtonMinimumScaleFactor: CGFloat {
        usesAccessibilityLayout ? 1 : 0.92
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayTemporaryGuidancePresentationState {
    let hasUser: Bool
    let isLoading: Bool
    let hasVisibleReading: Bool
    let readingError: AppError?

    var shouldShowTemporaryGuidance: Bool {
        guard hasUser, !isLoading, !hasVisibleReading else {
            return false
        }

        guard let readingError else {
            return false
        }

        if case .contentNotAvailable = readingError {
            return true
        }

        return false
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayTemporaryGuidanceState {
    let title: String
    let subtitle: String
    let bodyText: String
    let fortuneScore: Int
    let luckyNumbers: [Int]
    let powerColors: [String]

    var luckyNumbersText: String {
        luckyNumbers.map(String.init).joined(separator: " · ")
    }

    var luckyNumbersAccessibilityText: String {
        luckyNumbers.map(String.init).joined(separator: ", ")
    }

    var powerColorsText: String {
        powerColors.joined(separator: ", ")
    }

    var powerColorsAccessibilityText: String {
        powerColors.joined(separator: ", ")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let openingLines = [
        "The signal is softer today, so clarity comes from simplicity.",
        "Use today as a low-noise reset and stay close to what matters.",
        "Keep your pace steady and let intention set the tone."
    ]

    private static let closingLines = [
        "Small consistency is enough to keep momentum moving.",
        "Quiet progress today creates visible results soon.",
        "A clear, calm step now is more valuable than perfect timing."
    ]

    private static let categoryActionCues: [SituationCategory: String] = [
        .career: "commit to one high-leverage task before switching contexts",
        .love: "lead with a direct check-in and listen for what is unsaid",
        .social: "reach out to one person who energizes you and keep plans simple",
        .health: "protect your energy with one non-negotiable reset block today",
        .personalGrowth: "capture one insight in writing and turn it into a concrete next step"
    ]

    init(
        userID: UUID,
        zodiacSign: ZodiacSign,
        mbtiType: MBTIType,
        category: SituationCategory,
        date: Date
    ) {
        title = "\(category.rawValue) Focus"
        subtitle = "Live reading is catching up. Use this focused step for now."

        let dayKey = Self.dayFormatter.string(from: date)
        let seed =
            "\(userID.uuidString)|\(zodiacSign.rawValue)|\(mbtiType.rawValue)|\(category.rawValue)|temporary-guidance|\(dayKey)"
        var copyGenerator = SeededRandomGenerator(seed: "\(seed)|copy")
        let opening = Self.openingLines[
            copyGenerator.randomInt(in: 0...(Self.openingLines.count - 1))
        ]
        let actionCue = Self.categoryActionCues[category]
            ?? "choose one grounded priority and complete it"
        let closing = Self.closingLines[
            copyGenerator.randomInt(in: 0...(Self.closingLines.count - 1))
        ]

        bodyText = "\(opening) As a \(mbtiType.rawValue) \(zodiacSign.rawValue), \(actionCue). \(closing)"

        var extrasGenerator = SeededRandomGenerator(seed: "\(seed)|extras")
        fortuneScore = extrasGenerator.randomInt(in: 60...95)
        luckyNumbers = extrasGenerator.randomUniqueInts(count: 5, in: 1...99).sorted()
        powerColors = extrasGenerator.randomPowerColors()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayRetryActionState: Sendable {
    let isLoading: Bool
    let cooldownRemainingSeconds: Int

    static let cooldownDurationSeconds = 8
    static let cooldownNanoseconds: UInt64 =
        UInt64(cooldownDurationSeconds) * 1_000_000_000

    var isCoolingDown: Bool {
        cooldownRemainingSeconds > 0
    }

    private var clampedCooldownRemainingSeconds: Int {
        min(max(cooldownRemainingSeconds, 0), Self.cooldownDurationSeconds)
    }

    private var clampedCooldownSeconds: Int {
        max(clampedCooldownRemainingSeconds, 1)
    }

    var cooldownProgress: Double {
        guard isCoolingDown else {
            return 1
        }

        let elapsedSeconds = Self.cooldownDurationSeconds - clampedCooldownRemainingSeconds
        return Double(elapsedSeconds) / Double(Self.cooldownDurationSeconds)
    }

    var cooldownProgressPercent: Int {
        Int((cooldownProgress * 100).rounded())
    }

    var cooldownTimerLabel: String {
        guard isCoolingDown else {
            return "00:00"
        }

        let totalSeconds = clampedCooldownSeconds
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let minuteLabel = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        let secondLabel = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minuteLabel):\(secondLabel)"
    }

    var cooldownAccessibilityValue: String {
        guard isCoolingDown else {
            return "Cooldown complete."
        }

        return "\(cooldownProgressPercent)% complete, \(clampedCooldownSeconds) seconds remaining."
    }

    func cooldownAccessibilitySummary(autoRecoveryMessage: String?) -> String {
        guard let autoRecoveryMessage, !autoRecoveryMessage.isEmpty else {
            return cooldownAccessibilityValue
        }

        return "\(cooldownAccessibilityValue) \(autoRecoveryMessage)"
    }

    var isDisabled: Bool {
        isLoading || isCoolingDown
    }

    var allowsManualRefresh: Bool {
        !isCoolingDown && !isLoading
    }

    var showsProgress: Bool {
        isLoading
    }

    var bannerButtonTitle: String {
        if isLoading {
            return "Retrying..."
        }
        if isCoolingDown {
            return "Wait \(clampedCooldownSeconds)s"
        }
        return "Retry"
    }

    var bannerAccessibilityHint: String {
        if isLoading {
            return "Retry in progress"
        }
        if isCoolingDown {
            return "Retry is temporarily disabled. \(clampedCooldownSeconds) seconds remaining."
        }
        return "Attempts to load today's full reading again"
    }

    var cardButtonTitle: String {
        if isLoading {
            return "Trying Again..."
        }
        if isCoolingDown {
            return "Try Again in \(clampedCooldownSeconds)s"
        }
        return "Try Again"
    }

    var cardButtonSymbol: String {
        isCoolingDown ? "hourglass" : "arrow.clockwise"
    }

    var cardAccessibilityHint: String {
        if isLoading {
            return "Retry in progress"
        }
        if isCoolingDown {
            return "Retry is temporarily disabled. \(clampedCooldownSeconds) seconds remaining."
        }
        return "Attempts to load today's full reading again"
    }

    var cooldownMessage: String {
        let unit = clampedCooldownSeconds == 1 ? "second" : "seconds"
        return "We're giving live content a brief reset. Try again in \(clampedCooldownSeconds) \(unit)."
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayAutomaticLoadPolicy: Sendable {
    let isCoolingDown: Bool
    let readingError: AppError?

    var categoryLoadBehavior: TodayAutomaticCategoryLoadBehavior {
        guard isCoolingDown else {
            return .fullLoad
        }

        guard let readingError else {
            return .fullLoad
        }

        if case .contentNotAvailable = readingError {
            return .cacheOnly
        }

        return .fullLoad
    }

    var allowsAutomaticCategoryLoad: Bool {
        categoryLoadBehavior == .fullLoad
    }
}

@available(iOS 17.0, macOS 14.0, *)
enum TodayAutomaticCategoryLoadBehavior: Sendable, Equatable {
    case fullLoad
    case cacheOnly
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayAutomaticRecoveryPolicy: Sendable {
    let isLoading: Bool
    let readingError: AppError?
    let hasVisibleReading: Bool
    let automaticRecoveryAttempts: Int

    static let maxAutomaticRecoveryAttempts = 1

    private var isContentNotAvailableWithoutVisibleReading: Bool {
        guard let readingError else {
            return false
        }

        guard case .contentNotAvailable = readingError else {
            return false
        }

        return !hasVisibleReading
    }

    var hasReachedAutomaticRecoveryLimit: Bool {
        automaticRecoveryAttempts >= Self.maxAutomaticRecoveryAttempts
    }

    var isEligibleWhenCooldownCompletes: Bool {
        isContentNotAvailableWithoutVisibleReading
            && !hasReachedAutomaticRecoveryLimit
    }

    var shouldAttemptAutomaticRecovery: Bool {
        isEligibleWhenCooldownCompletes && !isLoading
    }

    var cooldownStatusSymbol: String? {
        if isEligibleWhenCooldownCompletes {
            return "clock.badge.checkmark"
        }

        if isContentNotAvailableWithoutVisibleReading && hasReachedAutomaticRecoveryLimit {
            return "arrow.clockwise.circle"
        }

        return nil
    }

    var cooldownStatusMessage: String? {
        if isEligibleWhenCooldownCompletes {
            return "We'll retry live guidance automatically when the cooldown ends."
        }

        if isContentNotAvailableWithoutVisibleReading && hasReachedAutomaticRecoveryLimit {
            return "One automatic retry already ran. Tap Try Again when the cooldown ends."
        }

        return nil
    }
}

@available(iOS 17.0, macOS 14.0, *)
enum TodayLoadErrorBannerTone: Sendable, Equatable {
    case informational
    case critical
}

@available(iOS 17.0, macOS 14.0, *)
struct TodayLoadErrorBannerPresentationState: Sendable {
    let readingError: AppError
    let hasVisibleReading: Bool
    let isCoolingDown: Bool
    let cooldownRemainingSeconds: Int
    let visibleReadingCreatedAt: Date?
    let now: Date

    init(
        readingError: AppError,
        hasVisibleReading: Bool,
        isCoolingDown: Bool,
        cooldownRemainingSeconds: Int,
        visibleReadingCreatedAt: Date? = nil,
        now: Date = Date()
    ) {
        self.readingError = readingError
        self.hasVisibleReading = hasVisibleReading
        self.isCoolingDown = isCoolingDown
        self.cooldownRemainingSeconds = cooldownRemainingSeconds
        self.visibleReadingCreatedAt = visibleReadingCreatedAt
        self.now = now
    }

    var tone: TodayLoadErrorBannerTone {
        guard hasVisibleReading else {
            return .critical
        }

        if case .contentNotAvailable = readingError {
            return .informational
        }

        return .critical
    }

    var iconSymbol: String {
        switch tone {
        case .informational:
            return "clock.arrow.circlepath"
        case .critical:
            return "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        if hasVisibleReading {
            if case .contentNotAvailable = readingError {
                return "Showing saved guidance"
            }
            return "Couldn't refresh right now"
        }

        return "Unable to load this reading"
    }

    var message: String {
        if hasVisibleReading {
            if case .contentNotAvailable = readingError {
                if isCoolingDown {
                    let remainingSeconds = max(cooldownRemainingSeconds, 1)
                    return "Live updates resume in \(remainingSeconds)s. You can browse saved categories now."
                }

                return "Live updates are back. Pull to refresh or tap Retry for a fresh reading."
            }
        }

        switch readingError {
        case .networkError:
            if hasVisibleReading {
                return "Showing your latest saved guidance. Check your connection and retry."
            }
            return "Check your connection and pull to refresh."
        case .authFailed:
            if hasVisibleReading {
                return "Showing your latest saved guidance. Sign in again in Profile, then retry."
            }
            return "Sign in again in Profile, then retry."
        case .contentNotAvailable:
            if hasVisibleReading {
                return "Showing your latest saved guidance while fresh content is temporarily unavailable."
            }
            return "Daily content is temporarily unavailable. Try again shortly."
        default:
            if hasVisibleReading {
                return "Showing your latest saved guidance. Please try again in a moment."
            }
            return "Please try again in a moment."
        }
    }

    var savedGuidanceRecencyLabel: String? {
        guard hasVisibleReading else {
            return nil
        }

        guard let recency = savedGuidanceRecency else {
            return "Saved recently"
        }

        switch recency {
        case .justNow:
            return "Saved just now"
        case .minutes(let value):
            return "Saved \(value)m ago"
        case .hours(let value):
            return "Saved \(value)h ago"
        case .days(let value):
            return "Saved \(value)d ago"
        }
    }

    var accessibilityValue: String {
        if let savedGuidanceAccessibilitySummary {
            return "\(message) \(savedGuidanceAccessibilitySummary)"
        }

        return message
    }

    private var savedGuidanceRecency: TodaySavedGuidanceRecency? {
        guard hasVisibleReading else {
            return nil
        }

        guard let visibleReadingCreatedAt else {
            return nil
        }

        let elapsedSeconds = max(0, now.timeIntervalSince(visibleReadingCreatedAt))
        let elapsedMinutes = Int(elapsedSeconds / 60)

        if elapsedMinutes < 1 {
            return .justNow
        }

        if elapsedMinutes < 60 {
            return .minutes(elapsedMinutes)
        }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 {
            return .hours(elapsedHours)
        }

        return .days(max(1, elapsedHours / 24))
    }

    private var savedGuidanceAccessibilitySummary: String? {
        guard hasVisibleReading else {
            return nil
        }

        guard let recency = savedGuidanceRecency else {
            return "Saved guidance is available."
        }

        switch recency {
        case .justNow:
            return "Saved guidance generated just now."
        case .minutes(let value):
            let unit = value == 1 ? "minute" : "minutes"
            return "Saved guidance generated \(value) \(unit) ago."
        case .hours(let value):
            let unit = value == 1 ? "hour" : "hours"
            return "Saved guidance generated \(value) \(unit) ago."
        case .days(let value):
            let unit = value == 1 ? "day" : "days"
            return "Saved guidance generated \(value) \(unit) ago."
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private enum TodaySavedGuidanceRecency: Sendable, Equatable {
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
}

@available(iOS 17.0, macOS 14.0, *)
struct TodaySharePresentationState: Sendable {
    private(set) var isPreparing = false
    private(set) var hasFailure = false

    var buttonTitle: String {
        isPreparing ? "Preparing..." : "Share Reading"
    }

    var buttonAccessibilityHint: String {
        isPreparing
            ? "Preparing share options"
            : "Opens the system share sheet"
    }

    var failureMessage: String? {
        guard hasFailure else { return nil }
        return "Couldn't prepare this share card. Please try again."
    }

    mutating func beginPreparing() {
        guard !isPreparing else { return }
        isPreparing = true
        hasFailure = false
    }

    mutating func finish(preparedItemCount: Int) {
        isPreparing = false
        hasFailure = preparedItemCount == 0
    }

    mutating func clearFailure() {
        hasFailure = false
    }
}

@available(iOS 17.0, macOS 14.0, *)
@available(iOS 17.0, macOS 14.0, *)
private struct TodayLoadingSkeleton: View {
    let cardBackground: Color
    let cardBorder: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            placeholderCard(height: 212)
            placeholderCard(height: 148)
            placeholderCard(height: 48)
        }
        .redacted(reason: .placeholder)
        .skeletonShimmer(active: !reduceMotion)
        .opacity(reduceMotion ? 0.95 : 1)
        .accessibilityHidden(true)
    }

    private func placeholderCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Placeholder")
                .font(.headline)
            Text("Placeholder content for daily horoscope reading layout.")
                .font(.body)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: height)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct TodayCooldownProgressBar: View {
    let progress: Double
    let trackColor: Color
    let fillColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * clampedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, width))
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.22),
                        value: clampedProgress
                    )
            }
        }
        .frame(height: 6)
    }
}

// MARK: - UIKit Activity View Controller bridge
#if os(iOS)
@available(iOS 17.0, *)
struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
