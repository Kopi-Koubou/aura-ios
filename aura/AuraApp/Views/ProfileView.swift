import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var showSignOut = false
    @State private var devTapCount = 0
    @State private var showDevTools = false
    @State private var streakReminderEnabled = StreakNotificationScheduler.isEnabled
    @State private var reminderTime = StreakNotificationScheduler.reminderTime
    @State private var retrogradeAlertsEnabled = RetrogradeAlertScheduler.isEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profileCard
                    subscriptionCard
                    reminderSection
                    retrogradeAlertSection
                    accountSection
                    appInfoSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationTitle("Profile")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showDevTools) {
                ProfileDevToolsView()
            }
            .confirmationDialog(
                "Sign Out",
                isPresented: $showSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await appState.clearAuthSession() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your local profile and cached readings will remain on this device.")
            }
            .task {
                await subscriptionManager.refreshStatus()
            }
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = appState.currentUser {
                HStack(spacing: 14) {
                    ZodiacIcon(sign: user.zodiacSign)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("\(user.zodiacSign.symbol) \(user.zodiacSign.rawValue.capitalized)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                streakRow

                mbtiCard(user: user)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Profile")
                        .font(.system(.title3, design: .serif).weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Complete onboarding to set up your profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }

    private func mbtiCard(user: UserProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(theme.accentFill())
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(user.mbtiType.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Personality type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.fieldBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var streakRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StreakTracker.currentStreak > 0 ? accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(StreakTracker.currentStreak > 0 ? theme.accentFill() : theme.fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(StreakTracker.currentStreak)-day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(StreakTracker.currentStreak > 0 ? "Keep it going!" : "Read today to start a streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.fieldBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: subscriptionManager.isPremium ? "crown.fill" : "crown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)

                Text(subscriptionStatusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(theme.accentFill())
            .clipShape(Capsule())

            if subscriptionManager.isPremium {
                Text("You have full access to all categories, extended readings, and the 7-day outlook.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                subscriptionDetailRows

                if let url = subscriptionManager.managementURL {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                            Text("Manage Subscription")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens subscription management in the App Store.")
                }

                Button("Restore Purchases") {
                    AuraHaptics.selection()
                    Task {
                        do {
                            try await subscriptionManager.restorePurchases()
                        } catch {}
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .disabled(subscriptionManager.isLoading)
            } else {
                Text("Unlock deeper daily guidance, all 5 categories, and your full weekly outlook.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    AuraHaptics.impact()
                    showPaywall = true
                } label: {
                    Text("View Premium")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(AuraPressButtonStyle())
                .frame(minHeight: 44)
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
    }

    // MARK: - Daily Reminder

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY REMINDER")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    settingIcon("bell.badge", tinted: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streak reminder")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Text("Get a nudge if you haven't read today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Toggle("", isOn: $streakReminderEnabled)
                        .labelsHidden()
                        .tint(accentColor)
                        .accessibilityLabel("Streak reminder")
                        .accessibilityHint(streakReminderEnabled ? "Disables the daily reading reminder." : "Enables a daily notification to protect your streak.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if streakReminderEnabled {
                    Divider()
                        .padding(.leading, 56)

                    HStack(spacing: 12) {
                        settingIcon("clock", tinted: false)

                        Text("Reminder time")
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .tint(accentColor)
                            .accessibilityLabel("Reminder time")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .onChange(of: streakReminderEnabled) { _, newValue in
                if newValue {
                    #if os(iOS)
                    StreakNotificationScheduler.requestPermissionAndEnable()
                    #endif
                    AnalyticsService.shared.track(.streakReminderEnabled)
                } else {
                    StreakNotificationScheduler.isEnabled = false
                    AnalyticsService.shared.track(.streakReminderDisabled)
                }
            }
            .onChange(of: reminderTime) { _, newValue in
                StreakNotificationScheduler.reminderTime = newValue
            }
        }
    }

    // MARK: - Retrograde Alerts (Premium)

    @ViewBuilder
    private var retrogradeAlertSection: some View {
        if subscriptionManager.isPremium {
            VStack(alignment: .leading, spacing: 12) {
                Text("RETROGRADE ALERTS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        settingIcon("arrow.uturn.backward.circle.fill", tinted: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Retrograde alerts")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)

                            Text("Get notified before planets go retrograde")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Toggle("", isOn: $retrogradeAlertsEnabled)
                            .labelsHidden()
                            .tint(accentColor)
                            .accessibilityLabel("Retrograde alerts")
                            .accessibilityHint(retrogradeAlertsEnabled ? "Disables retrograde notifications." : "Enables notifications before planetary retrogrades.")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(cardBorder, lineWidth: 1)
                }
                .onChange(of: retrogradeAlertsEnabled) { _, newValue in
                    if newValue {
                        #if os(iOS)
                        RetrogradeAlertScheduler.requestPermissionAndEnable()
                        #endif
                        AnalyticsService.shared.track(.retrogradeAlertEnabled)
                    } else {
                        RetrogradeAlertScheduler.isEnabled = false
                        AnalyticsService.shared.track(.retrogradeAlertDisabled)
                    }
                }
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                if appState.hasAuthAccessToken {
                    accountRow(
                        icon: "person.circle",
                        title: "Signed In",
                        detail: appState.authSessionAuthenticatedUserID
                    )

                    Divider()
                        .padding(.leading, 56)

                    Button {
                        showSignOut = true
                    } label: {
                        accountRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign Out",
                            detail: nil,
                            isDestructive: true
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                } else {
                    accountRow(
                        icon: "person.circle",
                        title: "Not Signed In",
                        detail: "Sign in to sync readings across devices"
                    )
                }
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
        }
    }

    private func accountRow(
        icon: String,
        title: String,
        detail: String?,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            settingIcon(icon, tinted: false, destructive: isDestructive)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isDestructive ? AuraTheme.destructiveRed : .primary)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("APP")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                infoRow(title: "Version", value: appVersion)
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            }
            .onTapGesture {
                devTapCount += 1
                if devTapCount >= 5 {
                    devTapCount = 0
                    AuraHaptics.success()
                    showDevTools = true
                }
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Setting Icon Helper

    private func settingIcon(_ systemName: String, tinted: Bool, destructive: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(destructive ? AuraTheme.destructiveRed : (tinted ? accentColor : .secondary))
            .frame(width: 28, height: 28)
            .background(tinted ? theme.accentFill() : (destructive ? AuraTheme.destructiveRed.opacity(0.1) : theme.fieldBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Computed

    @ViewBuilder
    private var subscriptionDetailRows: some View {
        VStack(spacing: 0) {
            if let planName = subscriptionPlanLabel {
                subscriptionInfoRow(title: "Plan", value: planName)
            }

            if let expiryDate = subscriptionManager.subscriptionExpirationDate {
                let label = subscriptionManager.isTrialing ? "Trial ends" : "Renews"
                subscriptionInfoRow(title: label, value: expiryDate.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.fieldBorder, lineWidth: 1)
        }
    }

    private func subscriptionInfoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var subscriptionPlanLabel: String? {
        guard let productId = subscriptionManager.activeProductIdentifier else {
            return nil
        }
        if productId == SubscriptionProduct.yearly.rawValue { return "Yearly" }
        if productId == SubscriptionProduct.monthly.rawValue { return "Monthly" }
        return nil
    }

    private var subscriptionStatusLabel: String {
        if subscriptionManager.isPremium {
            return subscriptionManager.isTrialing ? "Premium Trial" : "Premium Active"
        }
        return "Free Plan"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }
    private var accentColor: Color { theme.accent }
    private var backgroundColor: Color { theme.background }
    private var cardBackground: Color { theme.cardBackground }
    private var cardBorder: Color { theme.cardBorder }
}

// MARK: - Developer Tools (hidden behind 5-tap gesture)

@available(iOS 17.0, macOS 14.0, *)
struct ProfileDevToolsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var signInEmail = ""
    @State private var signInPassword = ""
    @State private var isSigningIn = false
    @State private var isSigningUp = false
    @State private var isRequestingPasswordReset = false
    @State private var signInStatusMessage: String?
    @State private var signUpStatusMessage: String?
    @State private var passwordResetStatusMessage: String?
    @State private var isReconcilingIdentity = false
    @State private var identityReconciliationStatusMessage: String?
    @State private var sessionAccessTokenDraft = ""
    @State private var sessionRefreshTokenDraft = ""
    @State private var includeSessionExpiry = false
    @State private var sessionExpiryDraft = Date().addingTimeInterval(3600)
    @State private var didSeedSessionDraft = false
    @State private var isApplyingSessionDraft = false
    @State private var sessionDraftStatusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                authSessionSection
                authPasswordSignInSection
                authSessionBootstrapSection
            }
            .navigationTitle("Developer Tools")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
#endif
            .task {
                await appState.refreshAuthSessionStatus()
                seedSessionDraftIfNeeded()
            }
        }
    }

    private var authSessionSection: some View {
        Section {
            LabeledContent("Status", value: appState.authSessionStatusMessage)

            if let authUserID = appState.authSessionAuthenticatedUserID {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auth User ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(authUserID)
                        .font(.footnote.monospaced())
                }
            }

            if let localUserID = appState.currentUser?.id.uuidString {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Profile ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localUserID)
                        .font(.footnote.monospaced())
                }
            }

            if appState.authSessionUserIDMismatch {
                Text("Authenticated user ID does not match local profile ID. Enforced auth mode will reject user-scoped requests until IDs match.")
                    .font(.footnote)
                    .foregroundStyle(.red)

                Button {
                    Task { await reconcileIdentityMismatch() }
                } label: {
                    if isReconcilingIdentity {
                        HStack {
                            ProgressView()
                            Text("Reconciling...")
                        }
                    } else {
                        Text("Reconcile Local Profile ID")
                    }
                }
                .disabled(isReconcilingIdentity)
            }

            if let identityReconciliationStatusMessage {
                Text(identityReconciliationStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let expiresAt = appState.authSessionExpiresAt {
                LabeledContent(
                    "Expires",
                    value: expiresAt.formatted(date: .abbreviated, time: .shortened)
                )
            }

            if let refreshError = appState.authSessionLastRefreshError {
                Text(refreshError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await appState.refreshAuthSession() }
            } label: {
                if appState.isRefreshingAuthSession {
                    HStack {
                        ProgressView()
                        Text("Refreshing...")
                    }
                } else {
                    Text("Refresh Session")
                }
            }
            .disabled(appState.isRefreshingAuthSession)

            Button("Clear Session", role: .destructive) {
                Task { await appState.clearAuthSession() }
            }
        } header: {
            Text("Auth Session")
        } footer: {
            Text("Reads tokens from runtime defaults first, then Info.plist fallback keys.")
        }
    }

    private var authPasswordSignInSection: some View {
        Section {
            TextField("Email", text: $signInEmail)
#if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)

            SecureField("Password", text: $signInPassword)

            Button {
                Task { await signInWithPassword() }
            } label: {
                if isSigningIn {
                    HStack {
                        ProgressView()
                        Text("Signing in...")
                    }
                } else {
                    Text("Sign In and Seed Session")
                }
            }
            .disabled(isSigningIn || isSigningUp || isRequestingPasswordReset || isSignInDraftIncomplete)

            Button {
                Task { await signUpWithPassword() }
            } label: {
                if isSigningUp {
                    HStack {
                        ProgressView()
                        Text("Signing up...")
                    }
                } else {
                    Text("Sign Up")
                }
            }
            .disabled(isSigningIn || isSigningUp || isRequestingPasswordReset || isSignInDraftIncomplete)

            Button {
                Task { await requestPasswordReset() }
            } label: {
                if isRequestingPasswordReset {
                    HStack {
                        ProgressView()
                        Text("Sending reset...")
                    }
                } else {
                    Text("Send Password Reset")
                }
            }
            .disabled(
                isSigningIn
                    || isSigningUp
                    || isRequestingPasswordReset
                    || signInEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if let signInStatusMessage {
                Text(signInStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let signUpStatusMessage {
                Text(signUpStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let passwordResetStatusMessage {
                Text(passwordResetStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Supabase Auth")
        } footer: {
            Text("Use password auth to sign in, create an account, or trigger password recovery without leaving the app.")
        }
    }

    private var authSessionBootstrapSection: some View {
        Section {
            TextField("Access token", text: $sessionAccessTokenDraft, axis: .vertical)
                .lineLimit(2...4)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .font(.footnote.monospaced())

            TextField("Refresh token", text: $sessionRefreshTokenDraft, axis: .vertical)
                .lineLimit(2...4)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .autocorrectionDisabled(true)
                .font(.footnote.monospaced())

            Toggle("Set explicit expiry", isOn: $includeSessionExpiry)

            if includeSessionExpiry {
                DatePicker(
                    "Expires",
                    selection: $sessionExpiryDraft,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            Button {
                Task { await applySessionDraft() }
            } label: {
                if isApplyingSessionDraft {
                    HStack {
                        ProgressView()
                        Text("Applying...")
                    }
                } else {
                    Text("Apply Session Tokens")
                }
            }
            .disabled(isApplyingSessionDraft || isSessionDraftEmpty)

            if let sessionDraftStatusMessage {
                Text(sessionDraftStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Session Bootstrap")
        } footer: {
            Text("Paste trusted Supabase tokens to seed refresh flow without rebuilding the app.")
        }
    }

    // MARK: - Helpers

    private func seedSessionDraftIfNeeded() {
        guard !didSeedSessionDraft else { return }
        sessionAccessTokenDraft = Secrets.supabaseAccessToken
        sessionRefreshTokenDraft = Secrets.supabaseRefreshToken
        if let expiresAt = appState.authSessionExpiresAt {
            includeSessionExpiry = true
            sessionExpiryDraft = expiresAt
        }
        didSeedSessionDraft = true
    }

    private var isSessionDraftEmpty: Bool {
        sessionAccessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && sessionRefreshTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSignInDraftIncomplete: Bool {
        signInEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || signInPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func signInWithPassword() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await appState.signInWithSupabase(email: signInEmail, password: signInPassword)
            signInPassword = ""
            identityReconciliationStatusMessage = nil
            signUpStatusMessage = nil
            passwordResetStatusMessage = nil
            if let authUserID = appState.authSessionAuthenticatedUserID {
                signInStatusMessage = "Signed in as \(authUserID)."
            } else {
                signInStatusMessage = "Sign-in succeeded and session tokens were stored."
            }
        } catch {
            signInStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signUpWithPassword() async {
        isSigningUp = true
        defer { isSigningUp = false }
        do {
            let outcome = try await appState.signUpWithSupabase(email: signInEmail, password: signInPassword)
            signInPassword = ""
            identityReconciliationStatusMessage = nil
            signInStatusMessage = nil
            passwordResetStatusMessage = nil
            switch outcome {
            case .authenticated(let userID):
                signUpStatusMessage = userID.map { "Sign-up succeeded and session is active for \($0)." }
                    ?? "Sign-up succeeded and session tokens were stored."
            case .confirmationRequired(let userID):
                signUpStatusMessage = userID.map { "Account created for \($0). Confirm your email, then sign in." }
                    ?? "Account created. Confirm your email, then sign in."
            }
        } catch {
            signUpStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func requestPasswordReset() async {
        isRequestingPasswordReset = true
        defer { isRequestingPasswordReset = false }
        do {
            try await appState.requestSupabasePasswordReset(email: signInEmail)
            signInPassword = ""
            signInStatusMessage = nil
            signUpStatusMessage = nil
            passwordResetStatusMessage = "Password reset email requested. Check your inbox."
        } catch {
            passwordResetStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reconcileIdentityMismatch() async {
        isReconcilingIdentity = true
        defer { isReconcilingIdentity = false }
        do {
            try await appState.reconcileAuthIdentityWithLocalProfile()
            if let localUserID = appState.currentUser?.id.uuidString {
                identityReconciliationStatusMessage = "Local profile now matches \(localUserID)."
            } else {
                identityReconciliationStatusMessage = "Local profile identity reconciled."
            }
        } catch {
            identityReconciliationStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applySessionDraft() async {
        isApplyingSessionDraft = true
        defer { isApplyingSessionDraft = false }
        do {
            try await appState.applyAuthSession(
                accessToken: sessionAccessTokenDraft,
                refreshToken: sessionRefreshTokenDraft,
                expiresAt: includeSessionExpiry ? sessionExpiryDraft : nil
            )
            sessionDraftStatusMessage = "Session tokens applied."
        } catch {
            sessionDraftStatusMessage = error.localizedDescription
        }
    }
}
