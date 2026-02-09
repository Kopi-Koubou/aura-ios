import Foundation
import SwiftUI
import RevenueCat

enum SubscriptionProduct: String {
    case monthly = "aura_premium_monthly"
    case yearly = "aura_premium_yearly"

    var price: String {
        switch self {
        case .monthly: return "$4.99/mo"
        case .yearly: return "$29.99/yr"
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
final class SubscriptionManager: NSObject, ObservableObject {
    static let shared = SubscriptionManager()

    @Published var customerInfo: CustomerInfo?
    @Published var offerings: Offerings?
    @Published var isPremium: Bool = false
    @Published var isTrialing: Bool = false
    @Published var isLoading: Bool = false
    @Published var purchaseError: String?

    static let entitlementID = "premium"

    private override init() {
        super.init()
    }

    func configure() {
        let apiKey = Secrets.revenueCatAPIKey
        guard !apiKey.isEmpty else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        Purchases.configure(withAPIKey: apiKey)
        Purchases.shared.delegate = self

        Task { await refreshStatus() }
    }

    func identify(userId: String) async {
        do {
            let (info, _) = try await Purchases.shared.logIn(userId)
            await updateFrom(customerInfo: info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            await updateFrom(customerInfo: info)
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func fetchOfferings() async {
        do {
            let fetched = try await Purchases.shared.offerings()
            await MainActor.run { self.offerings = fetched }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func purchase(package: Package) async throws -> Bool {
        await MainActor.run {
            isLoading = true
            purchaseError = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return false }
        await updateFrom(customerInfo: result.customerInfo)
        return true
    }

    func purchaseMonthly() async throws -> Bool {
        guard let offering = offerings?.current,
              let monthly = offering.availablePackages.first(where: {
                  $0.storeProduct.productIdentifier == SubscriptionProduct.monthly.rawValue
              }) else {
            throw AppError.purchaseFailed
        }
        return try await purchase(package: monthly)
    }

    func purchaseYearly() async throws -> Bool {
        guard let offering = offerings?.current,
              let yearly = offering.availablePackages.first(where: {
                  $0.storeProduct.productIdentifier == SubscriptionProduct.yearly.rawValue
              }) else {
            throw AppError.purchaseFailed
        }
        return try await purchase(package: yearly)
    }

    func restorePurchases() async throws {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        let info = try await Purchases.shared.restorePurchases()
        await updateFrom(customerInfo: info)
    }

    var monthlyPackage: Package? {
        offerings?.current?.availablePackages.first {
            $0.storeProduct.productIdentifier == SubscriptionProduct.monthly.rawValue
        }
    }

    var yearlyPackage: Package? {
        offerings?.current?.availablePackages.first {
            $0.storeProduct.productIdentifier == SubscriptionProduct.yearly.rawValue
        }
    }

    @MainActor
    private func updateFrom(customerInfo info: CustomerInfo) {
        self.customerInfo = info
        let entitlement = info.entitlements[Self.entitlementID]
        self.isPremium = entitlement?.isActive == true
        self.isTrialing = entitlement?.periodType == .trial
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension SubscriptionManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            updateFrom(customerInfo: customerInfo)
        }
    }
}
