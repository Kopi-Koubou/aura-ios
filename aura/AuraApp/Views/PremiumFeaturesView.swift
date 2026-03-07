import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct PremiumFeaturesView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasAttemptedOfferingsLoad = false
    @State private var isLoadingOfferings = false
    @State private var didLastOfferingsLoadFail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusCard
                    benefitsCard
                    pricingCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Premium")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .alert("Purchase Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .task {
                await subscriptionManager.refreshStatus()
                await refreshOfferings()
            }
            .refreshable {
                await subscriptionManager.refreshStatus()
                await refreshOfferings()
            }
            .onChange(of: availableProductIdentifiers) { _, _ in
                if !availableProductIdentifiers.isEmpty {
                    hasAttemptedOfferingsLoad = true
                    didLastOfferingsLoadFail = false
                }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: subscriptionManager.isPremium ? "crown.fill" : "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(subscriptionManager.isPremium ? "Premium Active" : "Upgrade Available")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.accentFill())
            .clipShape(Capsule())

            Text(subscriptionManager.isPremium ? "You're on Aura Premium" : "Unlock your full daily guidance")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if subscriptionManager.isPremium {
                Button("Restore Purchases") {
                    triggerSelectionFeedback()
                    Task { await restorePurchases() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .buttonStyle(AuraPressButtonStyle())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            } else {
                Button {
                    triggerImpactFeedback()
                    showPaywall = true
                } label: {
                    Text("View Plans")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(AuraPressButtonStyle())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Premium Benefits")
                .font(.headline)

            PremiumBenefitRow(icon: "infinity", title: "All 5 daily categories", subtitle: "Career, Love, Social, Health, and Growth.")
            PremiumBenefitRow(icon: "text.alignleft", title: "Extended readings", subtitle: "Long-form guidance for richer daily reflection.")
            PremiumBenefitRow(icon: "calendar", title: "7-day outlook", subtitle: "See what is building before it arrives.")
            PremiumBenefitRow(icon: "clock.arrow.circlepath", title: "Reading history", subtitle: "Revisit past readings whenever you need them.")
            PremiumBenefitRow(icon: "bell.badge", title: "Retrograde alerts", subtitle: "Get context before astrology-heavy days.")
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
    private var pricingCard: some View {
        if !subscriptionManager.isPremium {
            VStack(alignment: .leading, spacing: 12) {
                Text("Plan Preview")
                    .font(.headline)

                PricingPreviewRow(
                    title: "Yearly",
                    subtitle: "Best value for daily readers",
                    price: displayPrice(for: .yearly),
                    isLoading: isPlanLoading(for: .yearly),
                    isAvailable: isPlanAvailable(for: .yearly)
                )
                PricingPreviewRow(
                    title: "Monthly",
                    subtitle: "Flexible month-to-month",
                    price: displayPrice(for: .monthly),
                    isLoading: isPlanLoading(for: .monthly),
                    isAvailable: isPlanAvailable(for: .monthly)
                )

                if let footnote = offeringsPresentationState.selectorFootnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Includes a 7-day free trial where available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        }
    }

    private func restorePurchases() async {
        do {
            try await subscriptionManager.restorePurchases()
            triggerSuccessFeedback()
        } catch {
            triggerErrorFeedback()
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func displayPrice(for product: SubscriptionProduct) -> String {
        if isPlanLoading(for: product) {
            return "Loading..."
        }

        guard isPlanAvailable(for: product) else {
            return "Unavailable"
        }

        let packages = subscriptionManager.offerings?.current?.availablePackages ?? []
        if let localized = packages
            .first(where: { $0.storeProduct.productIdentifier == product.rawValue })?
            .localizedPriceString
        {
            return localized
        }
        return product.price
    }

    @MainActor
    private func refreshOfferings() async {
        guard !isLoadingOfferings else { return }

        isLoadingOfferings = true
        didLastOfferingsLoadFail = false

        let didFetchOfferings = await subscriptionManager.fetchOfferings()

        isLoadingOfferings = false
        hasAttemptedOfferingsLoad = true
        didLastOfferingsLoadFail = !didFetchOfferings
    }

    private static let planDisplayOrder: [SubscriptionProduct] = [.yearly, .monthly]

    private var availablePlans: [SubscriptionProduct] {
        Self.planDisplayOrder.filter { isPlanAvailable(for: $0) }
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

    private func isPlanAvailable(for product: SubscriptionProduct) -> Bool {
        let packages = subscriptionManager.offerings?.current?.availablePackages ?? []
        return packages.contains { $0.storeProduct.productIdentifier == product.rawValue }
    }

    private func isPlanLoading(for product: SubscriptionProduct) -> Bool {
        offeringsPresentationState.showsLoadingPlaceholder && !isPlanAvailable(for: product)
    }

    private var statusDescription: String {
        if subscriptionManager.isPremium {
            return subscriptionManager.isTrialing
                ? "Your trial is active. Enjoy every premium feature before renewal."
                : "All premium features are unlocked on this account."
        }
        return "Get deeper readings, full category access, and a weekly outlook."
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
private struct PremiumBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(AuraTheme(colorScheme: colorScheme).iconFill))

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
private struct PricingPreviewRow: View {
    let title: String
    let subtitle: String
    let price: String
    let isLoading: Bool
    let isAvailable: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle((isAvailable || isLoading) ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(price)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle((isAvailable || isLoading) ? .primary : .secondary)
        }
        .padding(14)
        .background(AuraTheme(colorScheme: colorScheme).rowFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .redacted(reason: isLoading ? .placeholder : [])
        .skeletonShimmer(active: isLoading)
        .opacity((isAvailable || isLoading) ? 1 : 0.72)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isLoading ? "Plan pricing loading." : (isAvailable ? "Plan available." : "Plan unavailable.")
        )
    }
}
