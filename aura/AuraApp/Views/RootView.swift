import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct RootView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sparkles")
                }
            
            WeekView()
                .tabItem {
                    Label("Week", systemImage: "calendar")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
            
            PremiumFeaturesView()
                .tabItem {
                    Label("Premium", systemImage: "crown")
                }
        }
    }
}
