import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if appState.isLoading && appState.currentUser == nil {
                RootLoadingView(
                    backgroundColor: backgroundColor,
                    cardBackground: cardBackground,
                    cardBorder: cardBorder
                )
            } else if appState.currentUser == nil {
                OnboardingView()
            } else {
                mainTabs
            }
        }
        .alert(
            appState.error?.alertTitle ?? "Something Went Wrong",
            isPresented: Binding(
                get: { appState.error != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.error = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    appState.error = nil
                }
            },
            message: {
                Text(appState.error?.localizedDescription ?? "Please try again.")
            }
        )
    }

    private var mainTabs: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sparkles")
                }

            WeekView()
                .tabItem {
                    Label("Week", systemImage: "calendar")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
        }
        .tint(AuraTheme(colorScheme: colorScheme).accent)
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var backgroundColor: Color { theme.background }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }
}

@available(iOS 17.0, macOS 14.0, *)
private struct RootLoadingView: View {
    let backgroundColor: Color
    let cardBackground: Color
    let cardBorder: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preparing your profile")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Syncing your account and today’s reading.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            placeholderCard(height: 112)
            placeholderCard(height: 156)
            placeholderCard(height: 48)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(backgroundColor.ignoresSafeArea())
        .redacted(reason: .placeholder)
        .skeletonShimmer(active: !reduceMotion)
        .opacity(reduceMotion ? 0.95 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your profile")
        .accessibilityHint("Aura is preparing your account and daily reading.")
    }

    private func placeholderCard(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Placeholder title")
                .font(.headline)

            Text("Placeholder body")
                .font(.subheadline)

            Text("Placeholder detail")
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(height: height, alignment: .topLeading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }
}

