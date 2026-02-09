# Technical Specification: Aura
## Horoscope/MBTI iOS App

**Version:** 1.0  
**Date:** February 7, 2026  
**Target Launch:** April 6, 2026  

---

## 1. Architecture Overview

### 1.1 Tech Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Frontend** | SwiftUI | Declarative UI framework |
| **State Management** | SwiftData | Local persistence (iOS 17+) |
| **Backend** | Supabase | Auth, database, edge functions |
| **AI Content** | OpenAI GPT-4o | Daily horoscope generation |
| **Payments** | RevenueCat | StoreKit wrapper, subscriptions |
| **Analytics** | PostHog | User behavior tracking |

### 1.2 Architecture Pattern: Clean Architecture + MVVM

```
┌─────────────────────────────────────────┐
│           Presentation Layer            │
│  (SwiftUI Views + ViewModels)           │
├─────────────────────────────────────────┤
│           Domain Layer                  │
│  (Use Cases, Entities, Repositories)    │
├─────────────────────────────────────────┤
│           Data Layer                    │
│  (SwiftData, Supabase Client, APIs)     │
└─────────────────────────────────────────┘
```

### 1.3 Data Flow

1. **Local-first:** All data stored in SwiftData
2. **Sync to cloud:** Supabase for cross-device sync
3. **AI generation:** OpenAI API with caching
4. **Offline support:** Graceful degradation when offline

---

## 2. Data Models

### 2.1 SwiftData Entities

```swift
// MARK: - User Profile
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var birthdate: Date
    var zodiacSign: ZodiacSign
    var mbtiType: MBTIType
    var createdAt: Date
    var updatedAt: Date
    
    // Relationships
    @Relationship(deleteRule: .cascade) var readings: [DailyReading]?
    @Relationship(deleteRule: .cascade) var mbtiResults: [MBTIResult]?
    
    init(name: String, birthdate: Date, mbtiType: MBTIType) {
        self.id = UUID()
        self.name = name
        self.birthdate = birthdate
        self.zodiacSign = ZodiacSign.from(date: birthdate)
        self.mbtiType = mbtiType
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Daily Reading
@Model
final class DailyReading {
    @Attribute(.unique) var id: UUID
    var date: Date
    var category: SituationCategory
    var content: String
    var fortuneScore: Int // 0-100
    var luckyNumbers: [Int]
    var powerColors: [String]
    var isPremium: Bool
    var createdAt: Date
    
    // Relationship
    var user: UserProfile?
    
    init(user: UserProfile, category: SituationCategory, content: String) {
        self.id = UUID()
        self.date = Date()
        self.category = category
        self.content = content
        self.fortuneScore = Int.random(in: 60...95)
        self.luckyNumbers = Array((1...99).shuffled().prefix(5))
        self.powerColors = ["Purple", "Gold", "Teal"]
        self.isPremium = false
        self.createdAt = Date()
        self.user = user
    }
}

// MARK: - MBTI Result
@Model
final class MBTIResult {
    @Attribute(.unique) var id: UUID
    var typeCode: String // e.g., "INTJ"
    var dimensionScores: [DimensionScore]
    var cognitiveFunctions: [CognitiveFunction]
    var strengths: [String]
    var weaknesses: [String]
    var takenAt: Date
    
    // Relationship
    var user: UserProfile?
    
    init(typeCode: String, dimensionScores: [DimensionScore]) {
        self.id = UUID()
        self.typeCode = typeCode
        self.dimensionScores = dimensionScores
        self.cognitiveFunctions = MBTIType.cognitiveFunctions(for: typeCode)
        self.strengths = MBTIType.strengths(for: typeCode)
        self.weaknesses = MBTIType.weaknesses(for: typeCode)
        self.takenAt = Date()
    }
}

// MARK: - Subscription Status
@Model
final class SubscriptionStatus {
    @Attribute(.unique) var id: UUID
    var tier: SubscriptionTier
    var expiresAt: Date?
    var isActive: Bool
    var updatedAt: Date
    
    init(tier: SubscriptionTier = .free) {
        self.id = UUID()
        self.tier = tier
        self.isActive = tier == .free
        self.updatedAt = Date()
    }
}

// MARK: - Enums
enum ZodiacSign: String, Codable, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces
    
    static func from(date: Date) -> ZodiacSign {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        
        switch (month, day) {
        case (3, 21...31), (4, 1...19): return .aries
        case (4, 20...30), (5, 1...20): return .taurus
        case (5, 21...31), (6, 1...20): return .gemini
        case (6, 21...30), (7, 1...22): return .cancer
        case (7, 23...31), (8, 1...22): return .leo
        case (8, 23...31), (9, 1...22): return .virgo
        case (9, 23...30), (10, 1...22): return .libra
        case (10, 23...31), (11, 1...21): return .scorpio
        case (11, 22...30), (12, 1...21): return .sagittarius
        case (12, 22...31), (1, 1...19): return .capricorn
        case (1, 20...31), (2, 1...18): return .aquarius
        default: return .pisces
        }
    }
}

enum MBTIType: String, Codable, CaseIterable {
    case INTJ, INTP, ENTJ, ENTP
    case INFJ, INFP, ENFJ, ENFP
    case ISTJ, ISFJ, ESTJ, ESFJ
    case ISTP, ISFP, ESTP, ESFP
}

enum SituationCategory: String, Codable, CaseIterable {
    case career = "Career"
    case love = "Love"
    case social = "Social"
    case health = "Health"
    case personalGrowth = "Personal Growth"
}

enum SubscriptionTier: String, Codable {
    case free = "free"
    case premium = "premium"
}

struct DimensionScore: Codable {
    let dimension: String // E/I, S/N, T/F, J/P
    let score: Double // -100 to 100
}

struct CognitiveFunction: Codable {
    let name: String
    let position: Int // 1-4 (dominant to inferior)
}
```

---

## 3. API Design

### 3.1 Supabase Schema (PostgreSQL)

```sql
-- Users table (syncs with SwiftData)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    birthdate DATE NOT NULL,
    zodiac_sign TEXT NOT NULL,
    mbti_type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Daily readings (generated content)
CREATE TABLE daily_readings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    category TEXT NOT NULL,
    content TEXT NOT NULL,
    fortune_score INTEGER CHECK (fortune_score BETWEEN 0 AND 100),
    lucky_numbers INTEGER[],
    power_colors TEXT[],
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, date, category)
);

-- MBTI results
CREATE TABLE mbti_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type_code TEXT NOT NULL,
    dimension_scores JSONB NOT NULL,
    cognitive_functions JSONB NOT NULL,
    taken_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscription tracking
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    tier TEXT NOT NULL DEFAULT 'free',
    revenuecat_customer_id TEXT,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE mbti_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can only access their own data" ON users
    FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users can only access their own readings" ON daily_readings
    FOR ALL USING (auth.uid() = user_id);
```

### 3.2 Edge Functions

```typescript
// supabase/functions/generate-horoscope/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { OpenAI } from 'https://esm.sh/openai@4.0.0'

serve(async (req) => {
  const { userId, zodiacSign, mbtiType, category, isPremium } = await req.json()
  
  const openai = new OpenAI({ apiKey: Deno.env.get('OPENAI_API_KEY') })
  
  const wordCount = isPremium ? '250-350' : '100-150'
  
  const prompt = `Generate a daily horoscope reading for a ${mbtiType} ${zodiacSign} focused on ${category}.

Tone: Positive, empowering, actionable.
Length: ${wordCount} words.
Include: Specific advice, cosmic context, actionable next step.

The reading should feel personalized to both their MBTI cognitive preferences and their zodiac sign's typical traits.`

  const completion = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: prompt }],
    max_tokens: isPremium ? 500 : 200,
  })

  const content = completion.choices[0].message.content
  
  // Store in database
  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  
  await supabase.from('daily_readings').insert({
    user_id: userId,
    date: new Date().toISOString().split('T')[0],
    category,
    content,
    is_premium: isPremium,
    fortune_score: Math.floor(Math.random() * 40) + 60,
    lucky_numbers: Array.from({length: 5}, () => Math.floor(Math.random() * 99) + 1),
    power_colors: ['Purple', 'Gold', 'Teal']
  })

  return new Response(JSON.stringify({ content }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

### 3.3 REST API Endpoints

| Endpoint | Method | Description | Auth |
|----------|--------|-------------|------|
| `/auth/signup` | POST | Email/password signup | Public |
| `/auth/signin` | POST | Email/password login | Public |
| `/functions/v1/generate-horoscope` | POST | Generate daily reading | JWT |
| `/functions/v1/mbti-calculate` | POST | Calculate MBTI from answers | JWT |
| `/rest/v1/daily_readings` | GET | Fetch user's readings | JWT |
| `/rest/v1/users` | GET | Get user profile | JWT |
| `/rest/v1/users` | PATCH | Update user profile | JWT |

---

## 4. UI Component Breakdown

### 4.1 Screen Structure

```
AuraApp
├── RootView
│   └── TabView
│       ├── TodayTab
│       │   ├── TodayView
│       │   │   ├── CategorySelector
│       │   │   ├── ReadingCard
│       │   │   └── FortuneCard
│       │   └── PremiumPaywall (modal)
│       ├── WeekTab
│       │   └── WeekView
│       │       └── WeekDayCell
│       ├── ProfileTab
│       │   └── ProfileView
│       │       ├── UserHeader
│       │       ├── MBTIProfileCard
│       │       └── SettingsSection
│       └── PremiumTab
│           └── PremiumFeaturesView
│
├── OnboardingFlow
│   ├── WelcomeView
│   ├── NameEntryView
│   ├── BirthdateView
│   ├── MBTIPathView
│   │   ├── KnownTypeView
│   │   └── MBTITestView
│   │       ├── QuestionView
│   │       └── ResultsView
│   └── FirstReadingView
│
└── PaywallModal
    └── SubscriptionView
```

### 4.2 Key Components

```swift
// MARK: - ReadingCard
struct ReadingCard: View {
    let reading: DailyReading
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                ZodiacIcon(sign: reading.user?.zodiacSign ?? .aries)
                VStack(alignment: .leading) {
                    Text(reading.user?.zodiacSign.rawValue.capitalized ?? "")
                        .font(.headline)
                    Text(reading.user?.mbtiType.rawValue ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(reading.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Content
            Text(reading.content)
                .font(.body)
                .lineLimit(isExpanded ? nil : 4)
                .onTapGesture { isExpanded.toggle() }
            
            // Expand indicator
            if !isExpanded {
                Text("Tap to read more...")
                    .font(.caption)
                    .foregroundStyle(.accent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - FortuneCard
struct FortuneCard: View {
    let reading: DailyReading
    @State private var animatedScore = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Fortune score
            HStack {
                Text("✨ Fortune")
                    .font(.headline)
                Spacer()
                Text("\(animatedScore)%")
                    .font(.title2.bold())
                    .foregroundStyle(fortuneColor)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fortuneGradient)
                        .frame(width: geo.size.width * CGFloat(animatedScore) / 100, height: 8)
                        .animation(.easeInOut(duration: 0.8), value: animatedScore)
                }
            }
            .frame(height: 8)
            
            // Lucky numbers & colors
            HStack {
                VStack(alignment: .leading) {
                    Text("Lucky Numbers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reading.luckyNumbers.map(String.init).joined(separator: ", "))
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Power Colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reading.powerColors.joined(separator: ", "))
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
                animatedScore = reading.fortuneScore
            }
        }
    }
    
    var fortuneColor: Color {
        switch reading.fortuneScore {
        case 80...100: return .green
        case 60...79: return .yellow
        default: return .orange
        }
    }
    
    var fortuneGradient: LinearGradient {
        LinearGradient(
            colors: [.yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - CategorySelector
struct CategorySelector: View {
    @Binding var selectedCategory: SituationCategory
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SituationCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CategoryChip: View {
    let category: SituationCategory
    let isSelected: Bool
    
    var body: some View {
        Text(category.rawValue)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}
```

---

## 5. State Management

### 5.1 App State (Observable)

```swift
// MARK: - AppState
@Observable
final class AppState {
    var currentUser: UserProfile?
    var subscriptionStatus: SubscriptionStatus
    var isLoading = false
    var error: AppError?
    
    private let userRepository: UserRepository
    private let subscriptionManager: SubscriptionManager
    
    init() {
        self.subscriptionStatus = SubscriptionStatus()
        self.userRepository = UserRepository()
        self.subscriptionManager = SubscriptionManager()
    }
    
    func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            currentUser = try await userRepository.fetchCurrentUser()
            await refreshSubscription()
        } catch {
            self.error = .failedToLoadUser
        }
    }
    
    func refreshSubscription() async {
        subscriptionStatus = await subscriptionManager.checkStatus()
    }
}

// MARK: - TodayViewModel
@Observable
final class TodayViewModel {
    var selectedCategory: SituationCategory = .career
    var currentReading: DailyReading?
    var isLoading = false
    var error: AppError?
    
    private let readingRepository: ReadingRepository
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        self.readingRepository = ReadingRepository()
    }
    
    func loadReading() async {
        guard let user = appState.currentUser else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Try local first
            if let cached = try await readingRepository.fetchLocal(
                user: user,
                category: selectedCategory,
                date: Date()
            ) {
                currentReading = cached
                return
            }
            
            // Generate new if needed
            currentReading = try await readingRepository.generate(
                user: user,
                category: selectedCategory
            )
        } catch {
            self.error = .failedToLoadReading
        }
    }
    
    func switchCategory(_ category: SituationCategory) {
        selectedCategory = category
        Task {
            await loadReading()
        }
    }
}
```

### 5.2 Dependency Injection

```swift
// MARK: - DependencyContainer
final class DependencyContainer {
    static let shared = DependencyContainer()
    
    lazy var supabaseClient: SupabaseClient = {
        SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseURL)!,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }()
    
    lazy var revenueCatClient: Purchases = {
        Purchases.configure(withAPIKey: Secrets.revenueCatAPIKey)
        return Purchases.shared
    }()
    
    lazy var openAIService: OpenAIService = {
        OpenAIService(apiKey: Secrets.openAIKey)
    }()
}

// MARK: - View Extension
extension View {
    func withDependencies() -> some View {
        self
            .environment(DependencyContainer.shared)
    }
}
```

---

## 6. Database Schema (Supabase)

### 6.1 Full Schema

```sql
-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    birthdate DATE NOT NULL,
    zodiac_sign TEXT NOT NULL CHECK (zodiac_sign IN (
        'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
        'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces'
    )),
    mbti_type TEXT NOT NULL CHECK (mbti_type IN (
        'INTJ', 'INTP', 'ENTJ', 'ENTP', 'INFJ', 'INFP', 'ENFJ', 'ENFP',
        'ISTJ', 'ISFJ', 'ESTJ', 'ESFJ', 'ISTP', 'ISFP', 'ESTP', 'ESFP'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Daily readings
CREATE TABLE public.daily_readings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    category TEXT NOT NULL CHECK (category IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth')),
    content TEXT NOT NULL,
    fortune_score INTEGER NOT NULL CHECK (fortune_score BETWEEN 0 AND 100),
    lucky_numbers INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    power_colors TEXT[] DEFAULT ARRAY[]::TEXT[],
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, date, category)
);

-- MBTI test results
CREATE TABLE public.mbti_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type_code TEXT NOT NULL,
    dimension_scores JSONB NOT NULL,
    cognitive_functions JSONB NOT NULL,
    strengths TEXT[] DEFAULT ARRAY[]::TEXT[],
    weaknesses TEXT[] DEFAULT ARRAY[]::TEXT[],
    taken_at TIMESTAMPTZ DEFAULT NOW()
);

-- Subscription tracking
CREATE TABLE public.subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'premium')),
    revenuecat_customer_id TEXT,
    original_purchase_date TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_daily_readings_user_date ON public.daily_readings(user_id, date);
CREATE INDEX idx_mbti_results_user ON public.mbti_results(user_id);
CREATE INDEX idx_subscriptions_user ON public.subscriptions(user_id);

-- RLS policies
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mbti_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can CRUD own data" ON public.users
    FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users can CRUD own readings" ON public.daily_readings
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can CRUD own MBTI results" ON public.mbti_results
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own subscription" ON public.subscriptions
    FOR SELECT USING (auth.uid() = user_id);

-- Function to update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

## 7. Authentication Flow

### 7.1 Auth Architecture

```
┌─────────────────────────────────────────┐
│          Auth Flow                      │
├─────────────────────────────────────────┤
│                                         │
│  1. User enters email/password          │
│           ↓                             │
│  2. Supabase Auth (signup/signin)       │
│           ↓                             │
│  3. Create user profile in SwiftData    │
│           ↓                             │
│  4. Sync to Supabase (edge function)    │
│           ↓                             │
│  5. RevenueCat identify(userId)         │
│           ↓                             │
│  6. App state updates → Main UI         │
│                                         │
└─────────────────────────────────────────┘
```

### 7.2 Auth Service

```swift
// MARK: - AuthService
final class AuthService {
    private let supabase: SupabaseClient
    private let modelContext: ModelContext
    
    init(supabase: SupabaseClient, modelContext: ModelContext) {
        self.supabase = supabase
        self.modelContext = modelContext
    }
    
    func signUp(email: String, password: String, name: String, birthdate: Date, mbtiType: MBTIType) async throws -> UserProfile {
        // 1. Supabase auth
        let authResponse = try await supabase.auth.signUp(
            email: email,
            password: password
        )
        
        guard let user = authResponse.user else {
            throw AuthError.signUpFailed
        }
        
        // 2. Create local profile
        let profile = UserProfile(
            name: name,
            birthdate: birthdate,
            mbtiType: mbtiType
        )
        profile.id = user.id // Use Supabase UUID
        
        modelContext.insert(profile)
        try modelContext.save()
        
        // 3. Sync to Supabase
        try await syncUserToSupabase(profile)
        
        // 4. RevenueCat identify
        Purchases.shared.logIn(user.id.uuidString)
        
        return profile
    }
    
    func signIn(email: String, password: String) async throws -> UserProfile {
        let authResponse = try await supabase.auth.signIn(
            email: email,
            password: password
        )
        
        guard let user = authResponse.user else {
            throw AuthError.signInFailed
        }
        
        // Fetch or create local profile
        if let existing = try fetchLocalUser(id: user.id) {
            return existing
        }
        
        // Fetch from Supabase
        return try await fetchUserFromSupabase(id: user.id)
    }
    
    private func syncUserToSupabase(_ profile: UserProfile) async throws {
        try await supabase
            .from("users")
            .insert([
                "id": profile.id,
                "name": profile.name,
                "birthdate": profile.birthdate.ISO8601Format(),
                "zodiac_sign": profile.zodiacSign.rawValue,
                "mbti_type": profile.mbtiType.rawValue
            ])
            .execute()
    }
}
```

---

## 8. RevenueCat Integration

### 8.1 Subscription Manager

```swift
// MARK: - SubscriptionManager
import RevenueCat

final class SubscriptionManager: ObservableObject {
    @Published var subscriptionStatus: SubscriptionStatus
    @Published var offerings: Offerings?
    @Published var isLoading = false
    
    init() {
        self.subscriptionStatus = SubscriptionStatus()
        configureRevenueCat()
    }
    
    private func configureRevenueCat() {
        Purchases.configure(withAPIKey: Secrets.revenueCatAPIKey)
        Purchases.shared.delegate = self
        
        // Fetch offerings
        Task {
            await fetchOfferings()
        }
    }
    
    func fetchOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            print("Failed to fetch offerings: \(error)")
        }
    }
    
    func checkStatus() async -> SubscriptionStatus {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            return SubscriptionStatus(from: customerInfo)
        } catch {
            return SubscriptionStatus(tier: .free)
        }
    }
    
    func purchase(_ package: Package) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)
        subscriptionStatus = SubscriptionStatus(from: customerInfo)
        
        return customerInfo.entitlements["premium"]?.isActive == true
    }
    
    func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        subscriptionStatus = SubscriptionStatus(from: customerInfo)
    }
}

extension SubscriptionManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        subscriptionStatus = SubscriptionStatus(from: customerInfo)
    }
}

// MARK: - SubscriptionStatus Extension
extension SubscriptionStatus {
    convenience init(from customerInfo: CustomerInfo) {
        let isPremium = customerInfo.entitlements["premium"]?.isActive == true
        self.init(tier: isPremium ? .premium : .free)
        self.isActive = isPremium
        self.expiresAt = customerInfo.entitlements["premium"]?.expirationDate
    }
}
```

### 8.2 Paywall Implementation

```swift
// MARK: - PaywallView
struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundStyle(.purple)
                    
                    Text("Unlock Your Full Potential")
                        .font(.title2.bold())
                    
                    Text("Get deeper insights and unlock all features")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Features
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "infinity", text: "All 5 daily categories")
                    FeatureRow(icon: "text.alignleft", text: "Extended readings (2x length)")
                    FeatureRow(icon: "calendar", text: "Full 7-day weekly outlook")
                    FeatureRow(icon: "clock.arrow.circlepath", text: "Unlimited historical access")
                    FeatureRow(icon: "bell.badge", text: "Retrograde alerts")
                }
                .padding()
                
                Spacer()
                
                // Pricing
                if let offering = subscriptionManager.offerings?.current {
                    VStack(spacing: 12) {
                        ForEach(offering.availablePackages, id: \.self) { package in
                            PackageButton(package: package) {
                                Task {
                                    do {
                                        let success = try await subscriptionManager.purchase(package)
                                        if success { dismiss() }
                                    } catch {
                                        // Show error
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Restore
                Button("Restore Purchases") {
                    Task {
                        try? await subscriptionManager.restorePurchases()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now") { dismiss() }
                }
            }
        }
    }
}

struct PackageButton: View {
    let package: Package
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(package.storeProduct.localizedTitle)
                        .font(.headline)
                    Text(package.storeProduct.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(package.localizedPriceString)
                    .font(.title3.bold())
            }
            .padding()
            .background(.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

```swift
// MARK: - ZodiacSignTests
import XCTest
@testable import Aura

final class ZodiacSignTests: XCTestCase {
    func testZodiacSignCalculation() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        XCTAssertEqual(ZodiacSign.from(date: dateFormatter.date(from: "2024-03-25")!), .aries)
        XCTAssertEqual(ZodiacSign.from(date: dateFormatter.date(from: "2024-07-15")!), .cancer)
        XCTAssertEqual(ZodiacSign.from(date: dateFormatter.date(from: "2024-12-25")!), .capricorn)
    }
}

// MARK: - MBTITests
final class MBTITests: XCTestCase {
    func testMBTICalculation() {
        let answers: [MBTIAnswer] = [
            MBTIAnswer(dimension: "E/I", score: -80), // Strong I
            MBTIAnswer(dimension: "S/N", score: 60),  // Moderate N
            MBTIAnswer(dimension: "T/F", score: -70), // Strong T
            MBTIAnswer(dimension: "J/P", score: 50),  // Moderate J
        ]
        
        let result = MBTICalculator.calculate(from: answers)
        XCTAssertEqual(result.typeCode, "INTJ")
    }
}

// MARK: - SubscriptionTests
final class SubscriptionTests: XCTestCase {
    func testFreeTierLimitations() {
        let status = SubscriptionStatus(tier: .free)
        XCTAssertFalse(status.canAccessPremiumContent)
        XCTAssertFalse(status.canViewHistoricalData)
    }
    
    func testPremiumTierAccess() {
        let status = SubscriptionStatus(tier: .premium)
        XCTAssertTrue(status.canAccessPremiumContent)
        XCTAssertTrue(status.canViewHistoricalData)
    }
}
```

### 9.2 UI Tests

```swift
// MARK: - OnboardingUITests
final class OnboardingUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--reset-data"]
        app.launch()
    }
    
    func testCompleteOnboarding() {
        // Welcome screen
        XCTAssertTrue(app.staticTexts["Welcome to Aura"].exists)
        app.buttons["Get Started"].tap()
        
        // Name entry
        let nameField = app.textFields["Enter your name"]
        nameField.tap()
        nameField.typeText("Alex")
        app.buttons["Continue"].tap()
        
        // Birthdate
        app.datePickers.element.tap()
        app.buttons["Continue"].tap()
        
        // MBTI path
        app.buttons["I know my MBTI type"].tap()
        app.buttons["INTJ"].tap()
        app.buttons["Continue"].tap()
        
        // Verify main screen
        XCTAssertTrue(app.staticTexts["Good morning, Alex"].waitForExistence(timeout: 5))
    }
}

// MARK: - TodayScreenUITests
final class TodayScreenUITests: XCTestCase {
    let app = XCUIApplication()
    
    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }
    
    func testCategorySwitching() {
        // Tap on Love category
        app.buttons["Love"].tap()
        
        // Verify reading updates
        XCTAssertTrue(app.staticTexts["Love"].exists)
    }
    
    func testPremiumPaywall() {
        // Try to access premium category (locked for free users)
        app.buttons["Career"].tap()
        
        // Verify paywall appears
        XCTAssertTrue(app.staticTexts["Unlock Your Full Potential"].waitForExistence(timeout: 3))
    }
}
```

### 9.3 Integration Tests

```swift
// MARK: - SyncIntegrationTests
final class SyncIntegrationTests: XCTestCase {
    var supabase: SupabaseClient!
    var modelContext: ModelContext!
    
    override func setUp() {
        supabase = SupabaseClient(
            supabaseURL: URL(string: ProcessInfo.processInfo.environment["TEST_SUPABASE_URL"]!)!,
            supabaseKey: ProcessInfo.processInfo.environment["TEST_SUPABASE_KEY"]!
        )
        
        let container = try! ModelContainer(for: UserProfile.self, DailyReading.self)
        modelContext = ModelContext(container)
    }
    
    func testReadingSync() async throws {
        // Create user locally
        let user = UserProfile(name: "Test", birthdate: Date(), mbtiType: .INTJ)
        modelContext.insert(user)
        
        // Create reading locally
        let reading = DailyReading(user: user, category: .career, content: "Test content")
        modelContext.insert(reading)
        
        // Sync to Supabase
        let syncService = SyncService(supabase: supabase, modelContext: modelContext)
        try await syncService.syncReadings(for: user)
        
        // Verify in Supabase
        let response = try await supabase
            .from("daily_readings")
            .select()
            .eq("user_id", value: user.id)
            .execute()
        
        XCTAssertEqual(response.count, 1)
    }
}
```

---

## 10. Deployment Plan

### 10.1 Environment Setup

```
┌─────────────────────────────────────────┐
│         Environments                    │
├─────────────────────────────────────────┤
│                                         │
│  Development                            │
│  ├── Supabase: dev project              │
│  ├── RevenueCat: sandbox API key        │
│  └── OpenAI: dev key                    │
│                                         │
│  Staging                                │
│  ├── Supabase: staging project          │
│  ├── RevenueCat: sandbox API key        │
│  └── OpenAI: prod key (rate limited)    │
│                                         │
│  Production                             │
│  ├── Supabase: prod project             │
│  ├── RevenueCat: prod API key           │
│  └── OpenAI: prod key                   │
│                                         │
└─────────────────────────────────────────┘
```

### 10.2 CI/CD Pipeline

```yaml
# .github/workflows/ios.yml
name: iOS Build & Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app
      
      - name: Run Tests
        run: xcodebuild test -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 15'

  build:
    needs: test
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app
      
      - name: Install certificates
        uses: apple-actions/import-codesign-certs@v2
        with:
          p12-file-base64: ${{ secrets.P12_BASE64 }}
          p12-password: ${{ secrets.P12_PASSWORD }}
      
      - name: Build & Archive
        run: |
          xcodebuild archive \
            -scheme Aura \
            -archivePath Aura.xcarchive \
            -destination 'generic/platform=iOS' \
            CODE_SIGN_IDENTITY="iPhone Distribution" \
            PROVISIONING_PROFILE_SPECIFIER="${{ secrets.PROVISIONING_PROFILE }}"
      
      - name: Upload to TestFlight
        run: |
          xcrun altool --upload-app \
            -f Aura.xcarchive/Products/Applications/Aura.app \
            -t ios \
            -u ${{ secrets.APPLE_ID }} \
            -p ${{ secrets.APP_PASSWORD }}
```

### 10.3 Launch Checklist

#### Pre-Launch (1 week before)
- [ ] App Store Connect listing complete
- [ ] Screenshots for all device sizes
- [ ] App Preview video uploaded
- [ ] Privacy policy published
- [ ] Terms of service published
- [ ] Support email configured
- [ ] Beta testing complete (TestFlight)
- [ ] RevenueCat products configured in production
- [ ] Supabase RLS policies tested
- [ ] OpenAI rate limits configured
- [ ] Analytics events validated

#### Launch Day
- [ ] Submit to App Store Review (1-2 days before)
- [ ] Monitor crash logs
- [ ] Monitor API error rates
- [ ] Respond to early user feedback
- [ ] Social media announcement
- [ ] Product Hunt launch

#### Post-Launch (Week 1)
- [ ] Daily active user monitoring
- [ ] Conversion rate tracking
- [ ] Bug fixes (if needed)
- [ ] First update planned

### 10.4 Secrets Management

```swift
// MARK: - Secrets (managed via Xcode build settings)
enum Secrets {
    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
    }
    
    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
    }
    
    static var revenueCatAPIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as! String
    }
    
    static var openAIKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as! String
    }
}

// Info.plist (template)
// Values injected via build settings:
// - SUPABASE_URL
// - SUPABASE_ANON_KEY
// - REVENUECAT_API_KEY
// - OPENAI_API_KEY
```

---

## 11. Security Considerations

| Area | Implementation |
|------|----------------|
| **Data Storage** | SwiftData encrypted at rest, Supabase RLS enforced |
| **API Keys** | Build-time injection, never hardcoded |
| **Auth** | Supabase Auth with email verification |
| **Network** | HTTPS only, certificate pinning for production |
| **Payments** | RevenueCat handles all payment data (PCI compliant) |
| **AI Content** | Input validation, rate limiting, content filtering |

---

## 12. Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| App Launch | < 2 seconds | Cold start to interactive |
| Reading Load | < 1 second | Local cache hit |
| AI Generation | < 3 seconds | Edge function response |
| App Size | < 50 MB | Download size |
| Memory Usage | < 150 MB | Peak usage |
| Battery Impact | Minimal | Background task optimization |

---

**Document Owner:** Kato  
**Last Updated:** February 7, 2026  
**Next Review:** After Sprint 1 completion
