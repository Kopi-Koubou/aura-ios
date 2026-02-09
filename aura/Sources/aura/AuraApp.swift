import SwiftUI
import SwiftData
import RevenueCat

@available(iOS 17.0, macOS 14.0, *)
@main
struct AuraApp: App {
    @State private var appState = AppState()
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    init() {
        SubscriptionManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environmentObject(subscriptionManager)
                .onAppear {
                    // ContentService setup happens via modelContainer callback
                }
        }
        .modelContainer(for: [UserProfile.self, DailyReading.self, MBTIResult.self, SubscriptionStatus.self]) { result in
            if case .success(let container) = result {
                let context = container.mainContext
                appState.setup(modelContext: context)
                Task { await appState.loadUser(modelContext: context) }
            }
        }
    }
}
