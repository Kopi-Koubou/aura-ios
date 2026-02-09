# Product Requirements Document

## Horoscope/MBTI App: Aura

**Version:** 1.0
**Date:** February 7, 2026
**Target Launch:** April 6, 2026
**Status:** Draft
**Priority:** P1 (Sprint Critical)

---

## 1. Executive Summary

Aura is a delightful iOS app that combines daily horoscope readings with MBTI personality insights. Users receive personalized cosmic guidance based on their zodiac sign and personality type, creating a unique daily ritual that feels deeply personal and actionable.

### Product Vision

To become the daily wellness companion for young adults who want meaningful guidance that actually resonates with who they are — not generic horoscopes or one-time personality tests.

### Core Value Proposition

- **Daily personalized horoscopes** based on zodiac sign + MBTI type
- **Personality test** with detailed cognitive function profiles
- **Combined insights** that fuse astrology timing with psychology
- **Freemium model** with genuine value in the free tier

### Target Outcomes

| Metric | Target | Timeline |
|--------|--------|----------|
| Monthly Revenue | $5,000 | Month 6 post-launch |
| Daily Active Users | 1,000 | Month 3 |
| Free-to-Paid Conversion | 3-5% | Month 6 |
| App Store Rating | 4.5+ stars | Ongoing |

---

## 2. User Personas

### Primary: The Self-Aware Seeker (Alex, 26)

- **Demographics:** 24-32, urban professional, disposable income
- **Behaviors:** Checks Instagram daily, uses Headspace/Calm, believes in astrology "for fun"
- **Pain points:** Co-Star feels too negative, 16Personalities is one-and-done
- **Goals:** Daily guidance that feels personal, actionable advice for decisions
- **Tech comfort:** High, iPhone user, subscribes to 2-3 apps

### Secondary: The MBTI Enthusiast (Jordan, 28)

- **Demographics:** 26-35, knowledge worker, personality psychology curious
- **Behaviors:** Has taken MBTI test before, knows their type, follows astrology accounts
- **Pain points:** Existing MBTI apps have no daily value, horoscope apps lack psychological depth
- **Goals:** Deeper understanding of their type, daily application of MBTI insights
- **Tech comfort:** High, early adopter

### Tertiary: The Casual Curious (Sam, 22)

- **Demographics:** 20-26, student or early career, price-sensitive
- **Behaviors:** Social media native, likes personality quizzes, checks horoscopes with friends
- **Pain points:** Most astrology apps feel too serious or too vague
- **Goals:** Fun daily content to share, low-commitment self-discovery
- **Tech comfort:** Very high, expects polished mobile experiences

---

## 3. User Stories

### Epic 1: Onboarding & First Experience

**US-1: Quick Setup**

As a first-time user, I want to set up my profile in under 60 seconds so I can immediately see value.

*Acceptance Criteria:*
- [ ] Welcome screen explains app purpose in one sentence
- [ ] Name entry with auto-focused keyboard
- [ ] Birthdate picker that calculates zodiac sign automatically
- [ ] Option to take MBTI test OR enter known type
- [ ] Clear progress indicator through onboarding
- [ ] Skip option for MBTI test (enter type manually)

**US-2: MBTI Assessment**

As a user without known MBTI type, I want to take an accurate personality test so the app understands my cognitive preferences.

*Acceptance Criteria:*
- [ ] 50-question assessment with clear progress bar
- [ ] Questions are relatable and not overly abstract
- [ ] Weighted scoring for 4 dimensions (E/I, S/N, T/F, J/P)
- [ ] Results page shows 4-letter type with percentage strengths
- [ ] Type profile includes: strengths, weaknesses, cognitive functions
- [ ] Option to retake test from settings

**US-3: First Daily Reading**

As a new user completing onboarding, I want to immediately see today's personalized reading so I feel the app's value.

*Acceptance Criteria:*
- [ ] Reading loads automatically after onboarding
- [ ] Shows personalized greeting with user's name
- [ ] Displays both zodiac sign and MBTI type
- [ ] Default to "Career" situation category
- [ ] Content feels specifically written for user's type + sign combination

### Epic 2: Daily Engagement

**US-4: Morning Ritual**

As a returning user, I want to quickly access today's guidance as part of my morning routine.

*Acceptance Criteria:*
- [ ] App opens to today's reading by default
- [ ] Content loads in under 2 seconds
- [ ] Date clearly displayed with day of week
- [ ] Swipe or tap to refresh if needed
- [ ] Reading timestamp shows "Today" or specific date

**US-5: Situation-Specific Guidance**

As a user facing a specific context, I want guidance tailored to that life area.

*Acceptance Criteria:*
- [ ] 5 category chips: Career, Love, Social, Health, Personal Growth
- [ ] Horizontal scroll selector with smooth animation
- [ ] Each category has unique content for the day
- [ ] Selected category persists during session
- [ ] Visual distinction between selected/unselected chips

**US-6: Fortune Details**

As a user, I want additional cosmic indicators to enhance my daily reading.

*Acceptance Criteria:*
- [ ] Overall fortune percentage (0-100%)
- [ ] Progress bar visualization
- [ ] Lucky numbers (3-5 numbers)
- [ ] Power colors (2-3 colors with hex codes)
- [ ] Compatible signs for the day

### Epic 3: Weekly & Extended Content

**US-7: Weekly Outlook**

As a user planning my week, I want to see upcoming cosmic trends.

*Acceptance Criteria:*
- [ ] Weekly view accessible from tab bar
- [ ] Shows next 7 days with fortune ratings
- [ ] Highlights high/low energy days
- [ ] Brief summary for each day
- [ ] Tap to expand daily details

**US-8: Type Deep Dive**

As an MBTI enthusiast, I want to explore detailed information about my personality type.

*Acceptance Criteria:*
- [ ] Full type profile accessible from Profile tab
- [ ] Cognitive function stack visualization
- [ ] Strengths and weaknesses sections
- [ ] Famous people with same type
- [ ] Type compatibility with other MBTI types

### Epic 4: Premium Features (Freemium)

**US-9: Premium Paywall**

As a free user, I want clear understanding of what premium offers before subscribing.

*Acceptance Criteria:*
- [ ] Paywall shows all premium features
- [ ] Free tier clearly marked with limitations
- [ ] Monthly/annual pricing options
- [ ] Trial period offered (7 days)
- [ ] Restore purchases option

**US-10: Advanced Readings**

As a premium subscriber, I want deeper insights beyond the daily basics.

*Acceptance Criteria:*
- [ ] Extended reading length (2x free tier)
- [ ] Weekly in-depth forecasts
- [ ] Monthly cosmic trends
- [ ] Retrograde alerts and guidance
- [ ] Personalized ritual recommendations

**US-11: Historical Access**

As a premium subscriber, I want to access past readings.

*Acceptance Criteria:*
- [ ] Calendar view to browse past dates
- [ ] Archive of all previous readings
- [ ] Search by date or keyword
- [ ] Export/share specific readings

---

## 4. Feature Specifications

### 4.1 Core Features

#### Daily Horoscope Engine

| Attribute | Specification |
|-----------|---------------|
| Content source | AI-generated via OpenAI API |
| Personalization | Zodiac sign × MBTI type × Day of week |
| Update frequency | Daily at 6 AM local time |
| Categories | Career, Love, Social, Health, Personal Growth |
| Content length | Free: 100-150 words; Premium: 250-350 words |
| Tone | Positive, empowering, actionable |

#### MBTI Assessment

| Attribute | Specification |
|-----------|---------------|
| Question count | 50 questions |
| Scoring method | Weighted dimension scoring |
| Dimensions | Extraversion/Introversion, Sensing/Intuition, Thinking/Feeling, Judging/Perceiving |
| Result accuracy | 85%+ correlation with official MBTI |
| Duration | 5-8 minutes |

#### Fortune Calculation

| Attribute | Specification |
|-----------|---------------|
| Overall fortune | 0-100% algorithmic score |
| Factors | Lunar phase, planetary positions, MBTI type energy patterns |
| Lucky numbers | 3-5 randomly generated but consistent per day |
| Power colors | 2-3 colors based on zodiac element + MBTI intuition |

### 4.2 Freemium Structure

#### Free Tier

| Feature | Limitation |
|---------|------------|
| Daily horoscope | 1 category per day (rotates or user choice) |
| MBTI test | Full test + basic profile |
| Weekly outlook | Current day only |
| Fortune details | Basic (fortune % + 1 lucky number) |
| Historical access | Last 7 days only |

#### Premium Tier ($4.99/month or $29.99/year)

| Feature | Benefit |
|---------|---------|
| Daily horoscope | All 5 categories, unlimited access |
| Content length | Extended readings (2x length) |
| Weekly outlook | Full 7-day forecast |
| Monthly trends | In-depth monthly cosmic analysis |
| Fortune details | Complete (all numbers, colors, compatibility) |
| Historical access | Unlimited archive |
| Ritual recommendations | Personalized daily rituals |
| Retrograde alerts | Push notifications for planetary events |

### 4.3 Technical Architecture

#### Stack

| Layer | Technology |
|-------|------------|
| Frontend | SwiftUI |
| State management | SwiftData (local-first) |
| Backend | Supabase (auth, edge functions) |
| AI content | OpenAI GPT-4o API |
| Payments | RevenueCat (StoreKit wrapper) |
| Analytics | PostHog |

#### Data Models

```swift
// User Profile
User {
  id: UUID
  name: String
  birthdate: Date
  zodiacSign: ZodiacSign
  mbtiType: MBTIType
  createdAt: Date
  subscriptionStatus: SubscriptionTier
}

// Daily Reading
Reading {
  id: UUID
  userId: UUID
  date: Date
  category: SituationCategory
  content: String
  fortuneScore: Int
  luckyNumbers: [Int]
  powerColors: [String]
  createdAt: Date
}

// MBTI Result
MBTIResult {
  id: UUID
  userId: UUID
  typeCode: String // e.g., "INTJ"
  dimensions: [DimensionScore]
  cognitiveFunctions: [FunctionStack]
  takenAt: Date
}
```

### 4.4 API Integration

#### OpenAI Content Generation

```
POST /v1/chat/completions

Prompt structure:
"Generate a daily horoscope reading for a [MBTI_TYPE] [ZODIAC_SIGN] 
on [DAY_OF_WEEK] focused on [CATEGORY]. 

Tone: Positive, empowering, actionable.
Length: [FREE/PREMIUM word count].
Include: Specific advice, cosmic context, actionable next step."

Response cached in SwiftData to minimize API calls.
```

#### Content Caching Strategy

| Content Type | Cache Duration | Fallback |
|--------------|----------------|----------|
| Daily readings | 24 hours | Generic reading for sign only |
| MBTI profiles | Permanent | Default profile |
| Weekly outlook | 7 days | Daily reading expanded |
| Fortune data | 24 hours | Randomized based on date seed |

---

## 5. User Flows

### 5.1 Onboarding Flow

```
App Launch
    ↓
Welcome Screen (value proposition)
    ↓
Name Entry → Birthdate Picker → Zodiac Display
    ↓
MBTI Path Selection
    ├── Known Type → Type Selection → Confirmation
    └── Take Test → Question 1-50 → Results → Type Profile
    ↓
First Daily Reading (immediate value)
    ↓
Main App (Today tab)
```

### 5.2 Daily Usage Flow

```
App Launch → Today's Reading (auto-load)
    ↓
Category Selection (Career/Love/Social/Health/Growth)
    ↓
Reading Card (scroll for full content)
    ↓
Fortune Card (swipe up or tap to expand)
    ↓
Tab Navigation
    ├── Today (daily reading)
    ├── Week (7-day outlook)
    ├── Profile (type info + settings)
    └── Premium (paywall/features)
```

### 5.3 Premium Conversion Flow

```
Free User hits premium feature
    ↓
Paywall Modal (feature preview)
    ↓
[Close] → Return to app
    ↓
[Subscribe] → StoreKit purchase
    ↓
Success → Unlock features
    ↓
Premium onboarding (feature tour)
```

---

## 6. UI/UX Specifications

### 6.1 Design System

#### Color Palette

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| Background | #FFFFFF | #0A0A0F | Main background |
| Surface | #F5F5F7 | #1C1C24 | Cards, sheets |
| Primary | #7C3AED | #A78BFA | Buttons, accents |
| Secondary | #EC4899 | #F472B6 | Highlights, fortune |
| Text Primary | #111827 | #F9FAFB | Headlines |
| Text Secondary | #6B7280 | #9CA3AF | Body text |

#### Gradients

- **Primary gradient:** `#0A0A0F` → `#1a1a3e` → `#2d1b4e` (background)
- **Accent gradient:** `#7C3AED` → `#EC4899` (buttons, highlights)
- **Fortune gradient:** `#F59E0B` → `#EF4444` (fortune score)

#### Typography

| Style | Font | Size | Weight |
|-------|------|------|--------|
| H1 | SF Pro Display | 28pt | Bold |
| H2 | SF Pro Display | 22pt | Semibold |
| H3 | SF Pro Text | 18pt | Semibold |
| Body | SF Pro Text | 16pt | Regular |
| Caption | SF Pro Text | 13pt | Medium |

#### Spacing

- Base unit: 8pt
- Card padding: 16pt
- Section spacing: 24pt
- Screen margins: 20pt

### 6.2 Key Screens

#### Today Screen

```
┌─────────────────────────────┐
│ Good morning, [Name] ☀️     │
│ Today, [Day] [Date]         │
├─────────────────────────────┤
│ [Career] [Love] [Social]... │ ← Category chips
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ ☀️ [Zodiac Icon]       │ │
│ │ [MBTI Type]             │ │
│ │                         │ │
│ │ Your Daily Guidance     │ │
│ │                         │ │
│ │ [Reading content...]    │ │
│ │                         │ │
│ │ Today's Cosmic Energy   │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │
│ │ ✨ Fortune: 85%         │ │
│ │ ████████████░░░         │ │
│ │ Lucky: 7, 14, 23        │ │
│ │ Colors: Purple, Gold    │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

#### MBTI Test Screen

```
┌─────────────────────────────┐
│ ← Discover Your Type        │
│ ████████░░ 42%              │ ← Progress bar
├─────────────────────────────┤
│ Question 21 of 50           │
│                             │
│ You prefer spending         │
│ weekends...                 │
│                             │
│ ○ With a big group of       │
│   friends                   │
│                             │
│ ○ With one or two close     │
│   friends                   │ ← Selected option
│                             │
│ ○ Alone, recharging         │
│                             │
├─────────────────────────────┤
│     [   Continue   ]        │
└─────────────────────────────┘
```

#### Profile Screen

```
┌─────────────────────────────┐
│ Profile                     │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ 👤 [Name]               │ │
│ │ ♏️ Scorpio · INTJ       │ │
│ │ [Edit Profile]          │ │
│ └─────────────────────────┘ │
│                             │
│ Your Personality            │
│ ┌─────────────────────────┐ │
│ │ The Architect (INTJ)    │ │
│ │                         │ │
│ │ [Cognitive functions]   │ │
│ │ [Strengths/Weaknesses]  │ │
│ │ [Compatibility]         │ │
│ └─────────────────────────┘ │
│                             │
│ Settings                    │
│ ┌─────────────────────────┐ │
│ │ Notifications     >     │ │
│ │ Subscription      >     │ │
│ │ Retake MBTI Test  >     │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

### 6.3 Animations & Interactions

| Interaction | Animation | Duration |
|-------------|-----------|----------|
| Tab switch | Fade + subtle slide | 200ms |
| Card tap | Scale 0.98 → 1.0 | 150ms |
| Category select | Background color morph | 200ms |
| Fortune reveal | Count up + progress fill | 800ms |
| Pull to refresh | Custom zodiac spinner | 1s |
| MBTI result | Staggered type reveal | 600ms |
| Paywall present | Bottom sheet slide | 300ms |

---

## 7. Monetization Strategy

### 7.1 Pricing

| Tier | Monthly | Annual | Trial |
|------|---------|--------|-------|
| Free | $0 | - | - |
| Premium | $4.99 | $29.99 (50% savings) | 7 days |

### 7.2 Revenue Model

| Revenue Stream | % of Total | Notes |
|----------------|------------|-------|
| Annual subscriptions | 60% | Preferred by committed users |
| Monthly subscriptions | 30% | Lower barrier, higher churn |
| One-time purchases | 10% | Future: readings packs, etc. |

### 7.3 Conversion Strategy

| Tactic | Implementation |
|--------|----------------|
| Value-first free tier | 1 free daily reading with full quality |
| Category lock teaser | Show locked categories with preview |
| Fortune detail gating | Hide some lucky numbers/colors |
| Weekly outlook limit | Free: today only; Premium: full week |
| Historical lock | Free: 7 days; Premium: unlimited |
| Contextual paywalls | Trigger when user tries locked feature |

---

## 8. Success Metrics

### 8.1 North Star Metric

**Daily Active Users (DAU)** who view their horoscope

### 8.2 Key Metrics

| Category | Metric | Target (M3) | Target (M6) |
|----------|--------|-------------|-------------|
| Acquisition | Downloads/month | 500 | 2,000 |
| Acquisition | CAC | <$2 | <$1.50 |
| Activation | Onboarding complete | 70% | 75% |
| Activation | MBTI test complete | 50% | 55% |
| Engagement | DAU/MAU ratio | 25% | 30% |
| Engagement | Avg session duration | 3 min | 4 min |
| Engagement | Categories viewed/session | 1.5 | 2.0 |
| Retention | D7 retention | 30% | 35% |
| Retention | D30 retention | 15% | 20% |
| Revenue | Free-to-paid conversion | 2% | 4% |
| Revenue | ARPU | $0.50 | $1.20 |
| Revenue | MRR | $500 | $5,000 |

### 8.3 Health Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| App crash rate | <0.5% | >1% |
| API error rate | <1% | >3% |
| Content load time | <2s | >4s |
| Subscription churn | <10%/mo | >15%/mo |
| Support tickets | <5/week | >10/week |

---

## 9. Go-to-Market

### 9.1 Launch Phases

#### Phase 1: Private Beta (Weeks 1-2)

- 50 TestFlight users
- Friends and family feedback
- Bug fixes and polish

#### Phase 2: Public Beta (Weeks 3-4)

- Open TestFlight link
- Social media announcement
- Gather early reviews

#### Phase 3: App Store Launch (Week 5)

- Submit to App Store
- Press kit to astrology/MBTI blogs
- Product Hunt launch

### 9.2 Marketing Channels

| Channel | Tactic | Budget |
|---------|--------|--------|
| Organic | TikTok/IG Reels content | Time |
| Community | Reddit (r/astrology, r/mbti) | Time |
| Influencer | Micro-influencers (10k-50k) | $500 |
| Paid | Apple Search Ads | $300/mo |
| PR | Press kit to wellness blogs | Time |

### 9.3 App Store Optimization

| Element | Content |
|---------|---------|
| App name | Aura: Horoscope & Personality |
| Subtitle | Daily guidance for your unique self |
| Keywords | horoscope, MBTI, astrology, personality, daily, zodiac |
| Screenshots | 5 screens: Today view, MBTI test, Fortune, Weekly, Profile |
| Preview video | 15-30 sec showing core flow |

---

## 10. Technical Roadmap

### Sprint 1: Foundation (Week 1-2)

- [ ] Project setup (SwiftUI + SwiftData + Supabase)
- [ ] User onboarding flow
- [ ] Zodiac calculation engine
- [ ] Basic Today screen UI

### Sprint 2: Core Features (Week 3-4)

- [ ] MBTI assessment (50 questions)
- [ ] MBTI result display
- [ ] Daily reading UI
- [ ] Category selector
- [ ] OpenAI integration

### Sprint 3: Premium (Week 5-6)

- [ ] RevenueCat integration
- [ ] Paywall implementation
- [ ] Premium feature gates
- [ ] Weekly outlook view
- [ ] Historical readings

### Sprint 4: Polish (Week 7-8)

- [ ] Animations and transitions
- [ ] Error handling
- [ ] Analytics integration
- [ ] Beta testing
- [ ] App Store preparation

---

## 11. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| OpenAI API costs exceed budget | Medium | High | Implement caching, usage limits |
| Content quality inconsistency | Medium | Medium | Prompt engineering, fallback content |
| App Store rejection | Low | High | Follow guidelines, test thoroughly |
| Low conversion rates | Medium | High | A/B test paywalls, adjust pricing |
| Competition from established apps | High | Medium | Focus on unique MBTI + astrology fusion |
| Subscription fatigue | Medium | Medium | Emphasize value, consider lifetime option |

---

## 12. Open Questions

| Question | Status | Notes |
|----------|--------|-------|
| Should we support Chinese zodiac in addition to Western? | Open | Could expand TAM significantly |
| Push notification strategy? | Open | Daily reading reminder? Retrograde alerts? |
| Social features (share readings)? | Open | Viral growth vs. privacy concerns |
| Android version timeline? | Open | Flutter vs. native Kotlin |
| Partnership with astrologers? | Open | Could differentiate content quality |
| Lifetime purchase option? | Open | One-time $49.99? |

---

## 13. Appendix

### A. MBTI Type Reference

| Type | Name | Population | Key Traits |
|------|------|------------|------------|
| INTJ | Architect | 2.1% | Strategic, independent, analytical |
| INTP | Logician | 3.3% | Inventive, theoretical, objective |
| ENTJ | Commander | 1.8% | Leadership, efficiency, strategic |
| ENTP | Debater | 3.2% | Innovative, curious, argumentative |
| INFJ | Advocate | 1.5% | Idealistic, insightful, determined |
| INFP | Mediator | 4.4% | Poetic, altruistic, reserved |
| ENFJ | Protagonist | 2.5% | Charismatic, inspiring, altruistic |
| ENFP | Campaigner | 8.1% | Enthusiastic, creative, sociable |
| ISTJ | Logistician | 11.6% | Practical, reliable, traditional |
| ISFJ | Defender | 13.8% | Protective, supportive, meticulous |
| ESTJ | Executive | 8.7% | Organized, practical, directive |
| ESFJ | Consul | 12.3% | Caring, social, popular |
| ISTP | Virtuoso | 5.4% | Practical, observant, spontaneous |
| ISFP | Adventurer | 8.8% | Flexible, artistic, sensitive |
| ESTP | Entrepreneur | 4.3% | Energetic, perceptive, direct |
| ESFP | Entertainer | 8.5% | Spontaneous, enthusiastic, friendly |

### B. Zodiac Sign Reference

| Sign | Dates | Element | Modality |
|------|-------|---------|----------|
| Aries | Mar 21 - Apr 19 | Fire | Cardinal |
| Taurus | Apr 20 - May 20 | Earth | Fixed |
| Gemini | May 21 - Jun 20 | Air | Mutable |
| Cancer | Jun 21 - Jul 22 | Water | Cardinal |
| Leo | Jul 23 - Aug 22 | Fire | Fixed |
| Virgo | Aug 23 - Sep 22 | Earth | Mutable |
| Libra | Sep 23 - Oct 22 | Air | Cardinal |
| Scorpio | Oct 23 - Nov 21 | Water | Fixed |
| Sagittarius | Nov 22 - Dec 21 | Fire | Mutable |
| Capricorn | Dec 22 - Jan 19 | Earth | Cardinal |
| Aquarius | Jan 20 - Feb 18 | Air | Fixed |
| Pisces | Feb 19 - Mar 20 | Water | Mutable |

### C. Content Generation Matrix

Daily content requirements:
- 16 MBTI types × 12 Zodiac signs × 7 Days × 5 Categories = 6,720 unique content combinations
- AI-generated on-demand with caching
- Fallback: Type-only or sign-only content if generation fails

---

**Document Owner:** Kato
**Last Updated:** February 7, 2026
**Next Review:** After implementation begins
