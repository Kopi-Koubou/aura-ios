import SwiftUI
import RevenueCat
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct PaywallView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedPlan: SubscriptionProduct = .yearly
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAttemptedOfferingsLoad = false
    @State private var isLoadingOfferings = false
    @State private var didLastOfferingsLoadFail = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    featuresSection
                    planSelector
                    ctaButton
                    restoreButton
                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Aura Premium")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") {
                        AnalyticsService.shared.track(.paywallDismissed)
                        dismiss()
                    }
                        .foregroundStyle(.secondary)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") {
                        AnalyticsService.shared.track(.paywallDismissed)
                        dismiss()
                    }
                }
            }
            #endif
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .task {
                AnalyticsService.shared.track(.paywallViewed)
                await refreshOfferings()
            }
            .onChange(of: availableProductIdentifiers) { _, _ in
                if !availableProductIdentifiers.isEmpty {
                    hasAttemptedOfferingsLoad = true
                    didLastOfferingsLoadFail = false
                }
                alignSelectedPlanWithAvailability()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.accentFill())
            .clipShape(Capsule())

            Text("Unlock Your Full Aura")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)

            Text("Deeper daily guidance designed for consistent reflection and better decisions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What You Unlock")
                .font(.headline)

            PremiumFeatureRow(icon: "infinity", title: "All 5 daily categories", subtitle: "Career, Love, Social, Health, Growth")
            PremiumFeatureRow(icon: "text.alignleft", title: "Extended readings", subtitle: "2x longer insights (250-350 words)")
            PremiumFeatureRow(icon: "calendar", title: "7-day outlook", subtitle: "Plan your week with cosmic guidance")
            PremiumFeatureRow(icon: "clock.arrow.circlepath", title: "Reading history", subtitle: "Access all your past readings")
            PremiumFeatureRow(icon: "bell.badge", title: "Retrograde alerts", subtitle: "Never be caught off guard")
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Plan")
                .font(.headline)

            PlanCard(
                title: "Yearly",
                subtitle: "Best value for daily readers",
                billingDetail: billingDetail(for: .yearly),
                price: priceLabel(for: .yearly),
                badge: planBadge(for: .yearly),
                accentColor: accentColor,
                accentFill: theme.accentFill(prominent: true),
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                isAvailable: isPackageAvailable(for: .yearly),
                isLoading: isPlanLoading(for: .yearly),
                isSelected: selectedPlan == .yearly,
                accessibilityValue: planAccessibilityValue(for: .yearly)
            ) {
                selectPlan(.yearly)
            }

            PlanCard(
                title: "Monthly",
                subtitle: "Flexible monthly access",
                billingDetail: billingDetail(for: .monthly),
                price: priceLabel(for: .monthly),
                badge: planBadge(for: .monthly),
                accentColor: accentColor,
                accentFill: theme.accentFill(prominent: true),
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                isAvailable: isPackageAvailable(for: .monthly),
                isLoading: isPlanLoading(for: .monthly),
                isSelected: selectedPlan == .monthly,
                accessibilityValue: planAccessibilityValue(for: .monthly)
            ) {
                selectPlan(.monthly)
            }

            if let footnote = offeringsPresentationState.selectorFootnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if offeringsPresentationState.showsRetryAction {
                Button {
                    triggerSelectionFeedback()
                    Task { await refreshOfferings() }
                } label: {
                    Label("Retry Pricing", systemImage: "arrow.clockwise")
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
                .disabled(isLoadingOfferings || subscriptionManager.isLoading)
                .accessibilityHint("Attempts to reload available plans from the App Store.")
            }
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        VStack(spacing: 8) {
            Button {
                triggerImpactFeedback()
                Task { await handlePurchase() }
            } label: {
                Group {
                    if subscriptionManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else if subscriptionManager.isPremium {
                        Text("Premium Active")
                            .font(.subheadline.weight(.semibold))
                    } else if offeringsPresentationState.showsLoadingPlaceholder {
                        Text("Loading Plans")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Start 7-Day Free Trial")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(AuraPressButtonStyle())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(
                subscriptionManager.isLoading
                    || subscriptionManager.isPremium
                    || offeringsPresentationState.showsLoadingPlaceholder
                    || !selectedPackageAvailable
            )
            .accessibilityHint(
                offeringsPresentationState.showsLoadingPlaceholder
                    ? "Plan pricing is still loading."
                    : selectedPackageAvailable
                    ? "Begins purchase for the selected plan."
                    : "Purchases are temporarily unavailable."
            )

            Text(trialNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        HStack(spacing: 12) {
            Button("Restore Purchases") {
                triggerSelectionFeedback()
                Task {
                    do {
                        try await subscriptionManager.restorePurchases()
                        if subscriptionManager.isPremium {
                            triggerSuccessFeedback()
                            dismiss()
                        }
                    } catch {
                        triggerErrorFeedback()
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .buttonStyle(AuraPressButtonStyle())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .disabled(subscriptionManager.isLoading)

            Spacer()
        }
    }

    private var legalLinks: some View {
        Text("7-day trial for eligible subscribers. Auto-renews unless canceled before renewal. Terms of Use and Privacy Policy apply.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    @MainActor
    private func refreshOfferings() async {
        guard !isLoadingOfferings else { return }

        isLoadingOfferings = true
        didLastOfferingsLoadFail = false

        let didFetchOfferings = await subscriptionManager.fetchOfferings()

        isLoadingOfferings = false
        hasAttemptedOfferingsLoad = true
        didLastOfferingsLoadFail = !didFetchOfferings
        alignSelectedPlanWithAvailability()
    }

    private func selectPlan(_ plan: SubscriptionProduct) {
        guard selectedPlan != plan else { return }
        guard isPackageAvailable(for: plan) else { return }

        if reduceMotion {
            selectedPlan = plan
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedPlan = plan
            }
        }

        triggerSelectionFeedback()
    }

    private func handlePurchase() async {
        guard selectedPackageAvailable else {
            triggerErrorFeedback()
            errorMessage = purchaseUnavailableMessage
            showError = true
            return
        }

        do {
            let success: Bool
            switch selectedPlan {
            case .monthly:
                success = try await subscriptionManager.purchaseMonthly()
            case .yearly:
                success = try await subscriptionManager.purchaseYearly()
            }
            if success {
                AnalyticsService.shared.track(.subscriptionCompleted, properties: [
                    "plan": selectedPlan == .yearly ? "yearly" : "monthly",
                ])
                triggerSuccessFeedback()
                dismiss()
            }
        } catch {
            triggerErrorFeedback()
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func package(for product: SubscriptionProduct) -> Package? {
        let packages = subscriptionManager.offerings?.current?.availablePackages ?? []
        return packages.first { $0.storeProduct.productIdentifier == product.rawValue }
    }

    private func isPackageAvailable(for product: SubscriptionProduct) -> Bool {
        package(for: product) != nil
    }

    private func formattedPrice(for product: SubscriptionProduct) -> String? {
        package(for: product)?.localizedPriceString
    }

    private func displayPrice(for product: SubscriptionProduct) -> String {
        formattedPrice(for: product) ?? product.price
    }

    private func priceLabel(for product: SubscriptionProduct) -> String {
        if isPlanLoading(for: product) {
            return "Loading..."
        }

        guard isPackageAvailable(for: product) else {
            return "Unavailable"
        }
        return displayPrice(for: product)
    }

    private var purchaseUnavailableMessage: String {
        offeringsPresentationState.purchaseUnavailableMessage
    }

    private var selectedPackageAvailable: Bool {
        isPackageAvailable(for: selectedPlan)
    }

    private func billingDetail(for product: SubscriptionProduct) -> String {
        if isPlanLoading(for: product) {
            return "Fetching App Store pricing"
        }

        guard isPackageAvailable(for: product) else {
            return "Currently unavailable"
        }

        switch product {
        case .monthly:
            return "Billed monthly"
        case .yearly:
            if let equivalent = yearlyEquivalentMonthlyPrice {
                return "Billed yearly (\(equivalent)/month)"
            }
            return "Billed yearly"
        }
    }

    private var yearlyBadge: String {
        if let savings = yearlySavingsPercent, savings > 0 {
            return "Save \(savings)%"
        }
        return "Best Value"
    }

    private func planBadge(for product: SubscriptionProduct) -> String? {
        if isPlanLoading(for: product) {
            return nil
        }

        guard isPackageAvailable(for: product) else {
            return "Unavailable"
        }

        if product == .yearly {
            return yearlyBadge
        }
        return nil
    }

    private func planAccessibilityValue(for product: SubscriptionProduct) -> String {
        if isPlanLoading(for: product) {
            return "Loading plan details. Not selected."
        }

        let details = billingDetail(for: product)
        let availability = isPackageAvailable(for: product) ? "Available" : "Unavailable"
        let selectedState = (selectedPlan == product && isPackageAvailable(for: product))
            ? "Selected"
            : "Not selected"
        return "\(priceLabel(for: product)). \(details). \(availability). \(selectedState)."
    }

    private var yearlyEquivalentMonthlyPrice: String? {
        guard let yearly = numericPrice(for: .yearly) else {
            return nil
        }
        return formatCurrency(yearly / Decimal(12))
    }

    private var yearlySavingsPercent: Int? {
        guard let monthlyPrice = numericPrice(for: .monthly),
              let yearlyCost = numericPrice(for: .yearly)
        else {
            return nil
        }

        let monthlyAnnualCost = monthlyPrice * Decimal(12)

        guard monthlyAnnualCost > yearlyCost else { return nil }

        let annual = NSDecimalNumber(decimal: monthlyAnnualCost).doubleValue
        guard annual > 0 else { return nil }

        let yearly = NSDecimalNumber(decimal: yearlyCost).doubleValue
        let ratio = ((annual - yearly) / annual) * 100
        let rounded = Int(ratio.rounded())
        return max(1, rounded)
    }

    private func numericPrice(for product: SubscriptionProduct) -> Decimal? {
        guard let package = package(for: product) else {
            return nil
        }

        let rawPrice = String(describing: package.storeProduct.price)
        return Decimal(string: rawPrice)
    }

    private func formatCurrency(_ amount: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = .current
        return formatter.string(from: NSDecimalNumber(decimal: amount))
    }

    private var trialNote: String {
        if subscriptionManager.isPremium {
            return "Premium is active on this account."
        }
        if offeringsPresentationState.showsLoadingPlaceholder {
            return "Checking available plans..."
        }
        if availablePlans.isEmpty {
            return purchaseUnavailableMessage
        }
        if !selectedPackageAvailable {
            return "Select an available plan to continue."
        }
        return "7-day free trial, then \(displayPrice(for: selectedPlan)). Cancel anytime."
    }

    private static let planDisplayOrder: [SubscriptionProduct] = [.yearly, .monthly]

    private var availablePlans: [SubscriptionProduct] {
        Self.planDisplayOrder.filter { isPackageAvailable(for: $0) }
    }

    private var availableProductIdentifiers: [String] {
        let identifiers = subscriptionManager.offerings?.current?.availablePackages
            .map { $0.storeProduct.productIdentifier } ?? []
        return identifiers.sorted()
    }

    private var offeringsPresentationState: PaywallOfferingsPresentationState {
        PaywallOfferingsPresentationState(
            isLoading: isLoadingOfferings,
            hasAttemptedLoad: hasAttemptedOfferingsLoad,
            didLastLoadFail: didLastOfferingsLoadFail,
            availablePlanCount: availablePlans.count,
            totalPlanCount: Self.planDisplayOrder.count
        )
    }

    private func isPlanLoading(for product: SubscriptionProduct) -> Bool {
        offeringsPresentationState.showsLoadingPlaceholder && !isPackageAvailable(for: product)
    }

    private func alignSelectedPlanWithAvailability() {
        guard !selectedPackageAvailable, let fallbackPlan = availablePlans.first else {
            return
        }

        if reduceMotion {
            selectedPlan = fallbackPlan
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedPlan = fallbackPlan
            }
        }
    }

    private var statusLabel: String {
        if subscriptionManager.isPremium {
            return subscriptionManager.isTrialing ? "Premium Trial" : "Premium Active"
        }
        return "Upgrade Available"
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var backgroundColor: Color { theme.background }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private func triggerSelectionFeedback() { AuraHaptics.selection() }

    private func triggerImpactFeedback() { AuraHaptics.impact() }

    private func triggerSuccessFeedback() { AuraHaptics.success() }

    private func triggerErrorFeedback() { AuraHaptics.error() }
}

@available(iOS 17.0, macOS 14.0, *)
struct PaywallOfferingsPresentationState: Sendable {
    let isLoading: Bool
    let hasAttemptedLoad: Bool
    let didLastLoadFail: Bool
    let availablePlanCount: Int
    let totalPlanCount: Int

    var hasAvailablePlans: Bool {
        availablePlanCount > 0
    }

    var showsLoadingPlaceholder: Bool {
        isLoading && !hasAvailablePlans
    }

    var canShowAvailabilityMessaging: Bool {
        hasAttemptedLoad && !isLoading
    }

    var showsUnavailableMessage: Bool {
        canShowAvailabilityMessaging && !hasAvailablePlans
    }

    var showsPartialAvailabilityMessage: Bool {
        canShowAvailabilityMessaging && hasAvailablePlans && availablePlanCount < totalPlanCount
    }

    var showsRetryAction: Bool {
        showsUnavailableMessage
    }

    var purchaseUnavailableMessage: String {
        didLastLoadFail
            ? "Unable to load plans right now. Check your App Store connection and try again."
            : "Purchases are temporarily unavailable. Check your App Store connection and try again."
    }

    var selectorFootnote: String? {
        if showsLoadingPlaceholder {
            return "Loading available plans..."
        }
        if showsUnavailableMessage {
            return purchaseUnavailableMessage
        }
        if showsPartialAvailabilityMessage {
            return "Some plan options are temporarily unavailable in your App Store region."
        }
        return nil
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct PaywallPlanCardPresentationState: Sendable {
    let dynamicTypeSize: DynamicTypeSize

    var usesStackedLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var usesStackedBadgeLayout: Bool {
        usesStackedLayout
    }
}

// MARK: - Subviews

@available(iOS 17.0, macOS 14.0, *)
private struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(AuraTheme(colorScheme: colorScheme).iconFill)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct PlanCard: View {
    let title: String
    let subtitle: String
    let billingDetail: String
    let price: String
    let badge: String?
    let accentColor: Color
    let accentFill: Color
    let cardBackground: Color
    let cardBorder: Color
    let isAvailable: Bool
    let isLoading: Bool
    let isSelected: Bool
    let accessibilityValue: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            cardContent
            .padding(14)
            .background((isSelected && isAvailable) ? theme.subtleFill() : cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((isSelected && isAvailable) ? accentColor : cardBorder, lineWidth: (isSelected && isAvailable) ? 2 : 1)
            }
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .skeletonShimmer(active: isLoading)
        .buttonStyle(AuraPressButtonStyle())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .disabled(isLoading || !isAvailable)
        .opacity((isAvailable || isLoading) ? 1 : 0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) plan")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            isLoading
                ? "Plan details are loading."
                : isAvailable
                ? (isSelected ? "Current selection." : "Double tap to select this plan.")
                : "This plan is currently unavailable."
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var cardContent: some View {
        if layoutState.usesStackedLayout {
            VStack(alignment: .leading, spacing: 10) {
                titleAndBadge

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(billingDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    priceText

                    if isSelected && isAvailable {
                        selectedLabel
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    titleAndBadge

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(billingDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    priceText

                    if isSelected && isAvailable {
                        selectedLabel
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var titleAndBadge: some View {
        if let badge {
            if layoutState.usesStackedBadgeLayout {
                VStack(alignment: .leading, spacing: 6) {
                    titleText
                    badgeLabel(badge)
                }
            } else {
                HStack(spacing: 8) {
                    titleText
                    badgeLabel(badge)
                }
            }
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle((isAvailable || isLoading) ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var priceText: some View {
        Text(price)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle((isAvailable || isLoading) ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var selectedLabel: some View {
        Label("Selected", systemImage: "checkmark.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(accentColor)
    }

    private func badgeLabel(_ badge: String) -> some View {
        Text(badge)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(badgeForeground)
            .background(badgeBackground)
            .clipShape(Capsule())
    }

    private var layoutState: PaywallPlanCardPresentationState {
        PaywallPlanCardPresentationState(dynamicTypeSize: dynamicTypeSize)
    }

    private var badgeForeground: Color {
        if !isAvailable {
            return Color.secondary
        }
        return accentColor
    }

    private var badgeBackground: Color {
        if !isAvailable {
            return theme.iconFill
        }
        return accentFill
    }
}
