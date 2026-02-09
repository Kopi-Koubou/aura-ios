import SwiftUI
import RevenueCat

@available(iOS 17.0, macOS 14.0, *)
struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared
    @State private var selectedPlan: SubscriptionProduct = .yearly
    @State private var showError = false
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    planSelector
                    ctaButton
                    trialNote
                    restoreButton
                    legalLinks
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color(red: 0.15, green: 0.05, blue: 0.25), Color(red: 0.05, green: 0.02, blue: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            #endif
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .task { await subscriptionManager.fetchOfferings() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, Color(red: 1.0, green: 0.6, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Unlock Your Full Aura")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text("Deeper insights, personalized just for you")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 20)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PremiumFeatureRow(icon: "infinity", title: "All 5 daily categories", subtitle: "Career, Love, Social, Health, Growth")
            PremiumFeatureRow(icon: "text.alignleft", title: "Extended readings", subtitle: "2x longer insights (250-350 words)")
            PremiumFeatureRow(icon: "calendar", title: "7-day outlook", subtitle: "Plan your week with cosmic guidance")
            PremiumFeatureRow(icon: "clock.arrow.circlepath", title: "Reading history", subtitle: "Access all your past readings")
            PremiumFeatureRow(icon: "bell.badge", title: "Retrograde alerts", subtitle: "Never be caught off guard")
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 12) {
            PlanCard(
                title: "Yearly",
                price: formattedPrice(for: .yearly) ?? "$29.99/yr",
                badge: "Save 50%",
                isSelected: selectedPlan == .yearly
            ) {
                selectedPlan = .yearly
            }

            PlanCard(
                title: "Monthly",
                price: formattedPrice(for: .monthly) ?? "$4.99/mo",
                badge: nil,
                isSelected: selectedPlan == .monthly
            ) {
                selectedPlan = .monthly
            }
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            Task { await handlePurchase() }
        } label: {
            Group {
                if subscriptionManager.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start 7-Day Free Trial")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.purple, Color(red: 0.6, green: 0.2, blue: 0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(subscriptionManager.isLoading)
    }

    private var trialNote: some View {
        Text("7-day free trial, then \(selectedPlan == .yearly ? "$29.99/year" : "$4.99/month"). Cancel anytime.")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                do {
                    try await subscriptionManager.restorePurchases()
                    if subscriptionManager.isPremium { dismiss() }
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Text("Terms of Use")
            Text("Privacy Policy")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.3))
    }

    // MARK: - Helpers

    private func handlePurchase() async {
        do {
            let success: Bool
            switch selectedPlan {
            case .monthly:
                success = try await subscriptionManager.purchaseMonthly()
            case .yearly:
                success = try await subscriptionManager.purchaseYearly()
            }
            if success { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formattedPrice(for product: SubscriptionProduct) -> String? {
        let packages = subscriptionManager.offerings?.current?.availablePackages ?? []
        return packages
            .first { $0.storeProduct.productIdentifier == product.rawValue }
            .map { $0.localizedPriceString }
    }
}

// MARK: - Subviews

@available(iOS 17.0, macOS 14.0, *)
private struct PremiumFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct PlanCard: View {
    let title: String
    let price: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 1.0, green: 0.6, blue: 0.2))
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Text(price)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.3) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
