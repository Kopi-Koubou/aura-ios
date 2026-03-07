import Foundation
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentStep = 0
    @State private var transitionDirection: OnboardingStepDirection = .forward
    @State private var authEmail = ""
    @State private var authPassword = ""
    @State private var isSigningIn = false
    @State private var isSigningUp = false
    @State private var isRequestingPasswordReset = false
    @State private var authStatusMessage: String?
    @State private var name = ""
    @State private var birthdate = Date()
    @State private var selectedMBTI: MBTIType?
    @State private var isCreatingProfile = false
    @State private var submissionError: String?
    private let finalStep = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader

                ScrollView {
                    stepContent
                        .id(currentStep)
                        .transition(stepTransition)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .background(backgroundColor.ignoresSafeArea())
            .tint(accentColor)
        }
    }

    private func advance() {
        guard currentStep < finalStep else { return }
        transitionDirection = .forward
        setStep(currentStep + 1)
    }

    private func retreat() {
        guard currentStep > 0 else { return }
        transitionDirection = .backward
        setStep(currentStep - 1)
    }

    private func setStep(_ step: Int) {
        guard step != currentStep else { return }

        if reduceMotion {
            currentStep = step
        } else {
            withAnimation(.easeOut(duration: 0.24)) {
                currentStep = step
            }
        }
    }

    private func createProfile() {
        guard let mbtiType = selectedMBTI else {
            submissionError = "Please select an MBTI type to continue."
            transitionDirection = .backward
            setStep(4)
            return
        }

        isCreatingProfile = true
        submissionError = nil

        Task { @MainActor in
            do {
                try await appState.completeOnboarding(
                    name: name,
                    birthdate: birthdate,
                    mbtiType: mbtiType
                )
            } catch {
                submissionError = error.localizedDescription
            }
            isCreatingProfile = false
        }
    }

    @MainActor
    private func signInWithPassword() async {
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            try await appState.signInWithSupabase(
                email: authEmail,
                password: authPassword
            )
            authPassword = ""
            if let authUserID = appState.authSessionAuthenticatedUserID {
                authStatusMessage = "Signed in as \(authUserID)."
            } else {
                authStatusMessage = "Sign-in succeeded."
            }
            advance()
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func signUpWithPassword() async {
        isSigningUp = true
        defer { isSigningUp = false }

        do {
            let outcome = try await appState.signUpWithSupabase(
                email: authEmail,
                password: authPassword
            )
            authPassword = ""

            switch outcome {
            case .authenticated(let userID):
                if let userID {
                    authStatusMessage = "Sign-up succeeded for \(userID)."
                } else {
                    authStatusMessage = "Sign-up succeeded."
                }
                advance()
            case .confirmationRequired(let userID):
                if let userID {
                    authStatusMessage = "Account created for \(userID). Confirm your email, then continue."
                } else {
                    authStatusMessage = "Account created. Confirm your email, then continue."
                }
            }
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func requestPasswordReset() async {
        isRequestingPasswordReset = true
        defer { isRequestingPasswordReset = false }

        do {
            try await appState.requestSupabasePasswordReset(email: authEmail)
            authStatusMessage = "Password reset email requested. Check your inbox."
        } catch {
            authStatusMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            WelcomeView(
                accentColor: accentColor,
                accentFill: theme.accentFill(prominent: true),
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                onContinue: advance
            )
        case 1:
            OnboardingAuthView(
                email: $authEmail,
                password: $authPassword,
                isAuthenticated: appState.hasAuthAccessToken,
                authenticatedUserID: appState.authSessionAuthenticatedUserID,
                requiresAuthenticationToContinue: Secrets.requiresAuthenticatedOnboarding,
                isSigningIn: isSigningIn,
                isSigningUp: isSigningUp,
                isRequestingPasswordReset: isRequestingPasswordReset,
                statusMessage: authStatusMessage,
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                fieldBackground: fieldBackground,
                fieldBorder: fieldBorder,
                onSignIn: {
                    Task { await signInWithPassword() }
                },
                onSignUp: {
                    Task { await signUpWithPassword() }
                },
                onPasswordReset: {
                    Task { await requestPasswordReset() }
                },
                onContinue: advance
            )
        case 2:
            NameEntryView(
                name: $name,
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                fieldBackground: fieldBackground,
                fieldBorder: fieldBorder,
                onContinue: advance
            )
        case 3:
            BirthdateView(
                birthdate: $birthdate,
                accentColor: accentColor,
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                onContinue: advance
            )
        case 4:
            MBTIPathView(
                selectedType: $selectedMBTI,
                accentColor: accentColor,
                accentFill: theme.accentFill(prominent: true),
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                fieldBackground: fieldBackground,
                fieldBorder: fieldBorder,
                onContinue: advance
            )
        case 5:
            CompletionView(
                isSubmitting: isCreatingProfile,
                errorMessage: submissionError,
                accentColor: accentColor,
                cardBackground: cardBackground,
                cardBorder: cardBorder,
                fieldBackground: fieldBackground,
                fieldBorder: fieldBorder,
                onFinish: createProfile
            )
        default:
            EmptyView()
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                if currentStep > 0 {
                    Button(action: retreat) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityHint("Returns to the previous onboarding step.")
                } else {
                    Color.clear
                        .frame(width: 72, height: 44)
                }

                Spacer()

                Text("Step \(currentStep + 1) of \(finalStep + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(fieldBackground)

                    Capsule()
                        .fill(accentColor)
                        .frame(width: proxy.size.width * progressValue)
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(currentStep + 1) of \(finalStep + 1)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var progressValue: CGFloat {
        CGFloat(currentStep + 1) / CGFloat(finalStep + 1)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else {
            return .identity
        }

        if transitionDirection == .forward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }

        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var backgroundColor: Color { theme.background }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private var fieldBackground: Color { theme.fieldBackground }

    private var fieldBorder: Color { theme.fieldBorder }
}

@available(iOS 17.0, macOS 14.0, *)
struct WelcomeView: View {
    let accentColor: Color
    let accentFill: Color
    let cardBackground: Color
    let cardBorder: Color
    let onContinue: () -> Void

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 52, height: 52)
                    .background(accentFill)
                    .clipShape(Circle())

                Text("Welcome to Aura")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Daily horoscope and MBTI guidance built to keep your reflection simple and consistent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(
                    icon: "sparkles.rectangle.stack",
                    title: "One focused reading each day",
                    subtitle: "Career, love, social, health, and growth when you need them."
                )
                OnboardingFeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Personality-tuned insights",
                    subtitle: "Your MBTI type shapes tone and practical suggestions."
                )
                OnboardingFeatureRow(
                    icon: "clock.arrow.circlepath",
                    title: "Built for daily rhythm",
                    subtitle: "Open Aura in seconds and keep your streak intentional."
                )
            }

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct OnboardingAuthView: View {
    @Binding var email: String
    @Binding var password: String
    let isAuthenticated: Bool
    let authenticatedUserID: String?
    let requiresAuthenticationToContinue: Bool
    let isSigningIn: Bool
    let isSigningUp: Bool
    let isRequestingPasswordReset: Bool
    let statusMessage: String?
    let cardBackground: Color
    let cardBorder: Color
    let fieldBackground: Color
    let fieldBorder: Color
    let onSignIn: () -> Void
    let onSignUp: () -> Void
    let onPasswordReset: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your account")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text(authorizationDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Session active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green, .secondary)
                        .font(.subheadline.weight(.semibold))
                    if let authenticatedUserID {
                        Text(authenticatedUserID)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(fieldBorder, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("you@example.com", text: $email)
#if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled(true)
                    .onboardingFieldStyle(background: fieldBackground, border: fieldBorder)
                    .accessibilityLabel("Email")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("Enter password", text: $password)
                    .onboardingFieldStyle(background: fieldBackground, border: fieldBorder)
                    .accessibilityLabel("Password")
            }

            Button {
                onSignIn()
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSigningIn ? "Signing in..." : "Sign In")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(hasPendingAuthAction || isCredentialDraftIncomplete)

            Button {
                onSignUp()
            } label: {
                HStack(spacing: 8) {
                    if isSigningUp {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSigningUp ? "Creating account..." : "Create Account")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.bordered)
            .disabled(hasPendingAuthAction || isCredentialDraftIncomplete)

            Button {
                onPasswordReset()
            } label: {
                HStack(spacing: 8) {
                    if isRequestingPasswordReset {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRequestingPasswordReset ? "Sending reset..." : "Reset Password")
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(hasPendingAuthAction || trimmedEmail.isEmpty)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(fieldBorder, lineWidth: 1)
                    }
            }

            if requiresAuthenticationToContinue && !isAuthenticated {
                Text("Sign in is required before continuing while auth mode is enforced.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAuthenticated || requiresAuthenticationToContinue {
                Button(continueButtonTitle, action: onContinue)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .buttonStyle(.borderedProminent)
                    .disabled(hasPendingAuthAction || (requiresAuthenticationToContinue && !isAuthenticated))
            } else {
                Button(continueButtonTitle, action: onContinue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
                    .disabled(hasPendingAuthAction)
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCredentialDraftIncomplete: Bool {
        trimmedEmail.isEmpty || trimmedPassword.isEmpty
    }

    private var hasPendingAuthAction: Bool {
        isSigningIn || isSigningUp || isRequestingPasswordReset
    }

    private var authorizationDescription: String {
        if requiresAuthenticationToContinue {
            return "Sign in to continue. Auth is currently required for daily readings."
        }

        return "Sign in to keep your readings synced across devices. You can also continue locally."
    }

    private var continueButtonTitle: String {
        if isAuthenticated {
            return "Continue"
        }

        return requiresAuthenticationToContinue ? "Sign In to Continue" : "Skip for Now"
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct NameEntryView: View {
    @Binding var name: String
    let cardBackground: Color
    let cardBorder: Color
    let fieldBackground: Color
    let fieldBorder: Color
    let onContinue: () -> Void

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should we call you?")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Your name appears in greetings and keeps the experience personal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("Enter your name", text: $name)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
                .autocorrectionDisabled(true)
                .onboardingFieldStyle(background: fieldBackground, border: fieldBorder)

            Button("Continue", action: onContinue)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct BirthdateView: View {
    @Binding var birthdate: Date
    let accentColor: Color
    let cardBackground: Color
    let cardBorder: Color
    let onContinue: () -> Void

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 8) {
                Text("When is your birthday?")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("We use your birthdate to determine your zodiac sign and daily horoscope.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DatePicker(
                "Birthdate",
                selection: $birthdate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(accentColor)

            Button("Continue", action: onContinue)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .buttonStyle(.borderedProminent)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct MBTIPathView: View {
    @Binding var selectedType: MBTIType?
    let accentColor: Color
    let accentFill: Color
    let cardBackground: Color
    let cardBorder: Color
    let fieldBackground: Color
    let fieldBorder: Color
    let onContinue: () -> Void

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What is your MBTI type?")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Choose the type that fits you best. This helps tune guidance tone and emphasis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(MBTIType.allCases, id: \.self) { type in
                    Button(type.rawValue) {
                        selectedType = type
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedType == type ? accentColor : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(selectedType == type ? accentFill : fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selectedType == type ? accentColor : fieldBorder, lineWidth: selectedType == type ? 1.5 : 1)
                    }
                    .accessibilityLabel(type.rawValue)
                    .accessibilityHint("Sets your MBTI type.")
                    .accessibilityAddTraits(selectedType == type ? .isSelected : [])
                }
            }

            Button("Continue") {
                onContinue()
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .buttonStyle(.borderedProminent)
            .disabled(selectedType == nil)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompletionView: View {
    let isSubmitting: Bool
    let errorMessage: String?
    let accentColor: Color
    let cardBackground: Color
    let cardBorder: Color
    let fieldBackground: Color
    let fieldBorder: Color
    let onFinish: () -> Void

    @State private var retrogradeAlertsEnabled = false

    private var activeRetrogrades: [RetrogradeEvent] {
        RetrogradeCatalog.activeRetrogrades
    }

    var body: some View {
        OnboardingSurfaceCard(cardBackground: cardBackground, cardBorder: cardBorder) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(accentColor)
                    .clipShape(Circle())

                Text("You’re all set")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Your profile is ready. Start with today’s reading and build a steady rhythm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !activeRetrogrades.isEmpty {
                retrogradeOptIn
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(action: onFinish) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSubmitting ? "Starting..." : "Start My Daily Reading")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
        }
    }

    private var retrogradeOptIn: some View {
        let summary = activeRetrogrades.map { "\($0.symbol) \($0.planet)" }.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(retrogradeAmberColor)

                Text("\(summary) in retrograde")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text("Get notified before retrogrades begin so you can prepare.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                #if os(iOS)
                RetrogradeAlertScheduler.requestPermissionAndEnable()
                #endif
                retrogradeAlertsEnabled = true
                AuraHaptics.success()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: retrogradeAlertsEnabled ? "checkmark.circle.fill" : "bell.badge")
                        .font(.caption2.weight(.semibold))
                    Text(retrogradeAlertsEnabled ? "Alerts enabled" : "Enable retrograde alerts")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(retrogradeAlertsEnabled ? .green : accentColor)
            .disabled(retrogradeAlertsEnabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(fieldBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Retrograde alert opt-in")
    }

    private var retrogradeAmberColor: Color { AuraTheme.retrogradeAmber }
}

@available(iOS 17.0, macOS 14.0, *)
private struct OnboardingSurfaceCard<Content: View>: View {
    let cardBackground: Color
    let cardBorder: Color
    let content: Content

    init(
        cardBackground: Color,
        cardBorder: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct OnboardingFieldStyle: ViewModifier {
    let background: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
    }
}

private extension View {
    func onboardingFieldStyle(background: Color, border: Color) -> some View {
        modifier(OnboardingFieldStyle(background: background, border: border))
    }
}

private enum OnboardingStepDirection {
    case forward
    case backward
}
