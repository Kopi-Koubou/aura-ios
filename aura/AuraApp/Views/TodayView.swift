import SwiftUI
import SwiftData

@available(iOS 17.0, macOS 14.0, *)
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedCategory: SituationCategory = .career
    @State private var currentReading: DailyReading?
    @State private var isLoading = false
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greetingHeader
                    CategorySelector(selectedCategory: $selectedCategory)

                    if isLoading {
                        ProgressView("Consulting the stars...")
                            .padding(.top, 40)
                    } else if let reading = currentReading {
                        ReadingCard(reading: reading)
                        premiumUpsellBanner(reading: reading)
                        FortuneCard(reading: reading)
                        shareButton(reading: reading)
                    } else {
                        ContentUnavailableView {
                            Label("No Reading Yet", systemImage: "sparkles")
                        } description: {
                            Text("Your daily horoscope will appear here")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .onChange(of: selectedCategory) { _, _ in
                Task { await loadReading() }
            }
            .task { await loadReading() }
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title2.bold())
                if let user = appState.currentUser {
                    Text("\(user.zodiacSign.symbol) \(user.zodiacSign.rawValue.capitalized) \u{00B7} \(user.mbtiType.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if !subscriptionManager.isPremium {
                Button {
                    showPaywall = true
                } label: {
                    Label("Premium", systemImage: "crown.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [.purple, Color(red: 0.6, green: 0.2, blue: 0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Premium Upsell

    @ViewBuilder
    private func premiumUpsellBanner(reading: DailyReading) -> some View {
        if !subscriptionManager.isPremium && !reading.isPremium {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get the Full Reading")
                            .font(.subheadline.bold())
                        Text("Unlock 2x longer insights with Premium")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.15), Color.purple.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Share

    @ViewBuilder
    private func shareButton(reading: DailyReading) -> some View {
        Button {
            Task {
                let service = ShareService()
                shareItems = await service.shareItems(for: reading)
                if !shareItems.isEmpty {
                    showShareSheet = true
                }
            }
        } label: {
            Label("Share Reading", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func loadReading() async {
        guard let user = appState.currentUser else { return }
        isLoading = true
        defer { isLoading = false }

        guard let contentService = appState.contentService else { return }

        do {
            currentReading = try await contentService.todayReading(for: user, category: selectedCategory)
        } catch {
            appState.error = .failedToLoadReading
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
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
