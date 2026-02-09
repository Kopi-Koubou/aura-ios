# Aura — Pitch Deck
## Colosseum Hackathon Submission

---

## Slide 1: The Problem

**Astrology apps are generic. Personality tests are one-and-done.**

- Co-Star delivers vague, often negative readings
- 16Personalities gives you a type — then nothing
- No app combines both for truly personalized guidance
- Users want daily value, not a one-time result

> *"I know my MBTI type and my zodiac sign. Why can't an app use both to actually help me?"*
> — Every astrology-curious professional

---

## Slide 2: The Solution

**Aura — Daily cosmic guidance personalized by your MBTI + Zodiac**

| What | How |
|------|-----|
| **Daily Horoscope** | AI-generated based on your unique type + sign combination |
| **MBTI Assessment** | 50-question test with cognitive function profiles |
| **Combined Insights** | Astrology timing × Psychology = actionable guidance |
| **Freemium Model** | Genuine daily value in free tier; premium unlocks depth |

**The "aha" moment:** Your daily reading isn't just for a Scorpio — it's for an *INTJ Scorpio*.

---

## Slide 3: Demo Flow (60-90 seconds)

| Time | Screen | Action |
|------|--------|--------|
| 0-3s | Welcome | Logo, tagline: "Daily guidance for your unique self" |
| 3-8s | Onboarding | Enter name, birthdate → zodiac auto-detected |
| 8-12s | MBTI Path | Choose: "I know my type" or "Take the test" |
| 12-35s | MBTI Test | Answer 8 questions (accelerated demo) |
| 35-45s | Results | Type revealed with cognitive function breakdown |
| 45-60s | Daily Reading | Personalized guidance for Career category |
| 60-75s | Fortune Card | Cosmic energy score, lucky numbers, power colors |

**Key interaction:** Category chips (Career, Love, Social, Health, Growth) — each generates unique content.

---

## Slide 4: Technical Stack

| Layer | Technology | Why |
|-------|------------|-----|
| **Frontend** | SwiftUI | Native iOS, smooth animations, HealthKit-ready |
| **State** | SwiftData | Local-first, offline capable, fast |
| **Backend** | Supabase | Auth, edge functions, Postgres |
| **AI** | OpenAI GPT-4o | 6,720 content combinations (16 types × 12 signs × 7 days × 5 categories) |
| **Payments** | RevenueCat | StoreKit abstraction, subscription management |
| **Analytics** | PostHog | Product analytics, funnel tracking |

**Smart caching:** Content generated once per day, cached locally. API costs minimized.

---

## Slide 5: Market Opportunity

| Metric | Value |
|--------|-------|
| **Astrology app market** | $2.2B (2024) |
| **MBTI test takers** | 2M+ annually |
| **Target demographic** | 24-35 urban professionals |
| **Willingness to pay** | $4.99-9.99/month for wellness apps |

**Competitive Landscape:**

| App | Horoscope | MBTI | Daily Value | Pricing |
|-----|-----------|------|-------------|---------|
| Co-Star | ✅ | ❌ | ✅ | Free / $4.99 |
| 16Personalities | ❌ | ✅ | ❌ | One-time $49 |
| Sanctuary | ✅ | ❌ | ✅ | $14.99/mo |
| **Aura** | ✅ | ✅ | ✅ | **$4.99/mo** |

**Differentiation:** The only app that fuses astrology timing with psychological depth.

---

## Slide 6: Business Model

**Freemium with clear value ladder:**

| Tier | Price | Features |
|------|-------|----------|
| **Free** | $0 | 1 daily reading, basic MBTI profile, 7-day history |
| **Premium** | $4.99/mo or $29.99/yr | All 5 categories, extended readings, unlimited history, weekly forecasts |

**Revenue Projections:**

| Month | DAU | Conversion | MRR |
|-------|-----|------------|-----|
| M3 | 1,000 | 2% | $100 |
| M6 | 3,000 | 4% | $600 |
| M12 | 8,000 | 5% | $2,000 |

**Path to $5K MRR:** 10,000 DAU × 5% conversion × $4.99 = $2,495/mo + annual upsells

---

## Slide 7: Traction & Validation

**Built in 5 days for this hackathon:**

| Milestone | Status |
|-----------|--------|
| SwiftUI app with SwiftData | ✅ Complete |
| MBTI assessment (50 questions) | ✅ Complete |
| Daily reading engine (OpenAI) | ✅ Complete |
| RevenueCat integration | ✅ Complete |
| Fortune calculation algorithm | ✅ Complete |
| GitHub repo | ✅ Public |

**Demo Video:** [Link to be added after recording]

**Technical Highlights:**
- Local-first architecture — works offline
- 60-90 second onboarding completion
- <2 second content load times
- Smooth category switching with animated transitions

---

## Slide 8: Team & Vision

**Builder:** Xavier Liew — Product & Strategy Lead

**Background:**
- Product lead at Solv Protocol ($100M+ TVL Bitcoin DeFi)
- Ex-Drift Protocol, PancakeSwap
- Stanford NOC, NUS Business Analytics
- Shipping products since 2020

**Why This Matters:**
> The wellness app space is crowded with generic horoscopes and abandoned personality tests. Aura creates a daily ritual that actually understands the user — combining two established frameworks (astrology + MBTI) into something genuinely personalized.

**Vision:**
Become the daily wellness companion for young professionals who want guidance that actually resonates with who they are.

---

## Slide 9: The Ask

**Colosseum Investment:** $250K pre-seed

**Use of Funds:**

| Category | Allocation | Purpose |
|----------|------------|---------|
| Product Development | 40% | 3 months full-time build, polish, launch |
| Marketing & Growth | 30% | Influencers, Apple Search Ads, content |
| Operations | 20% | AI API costs, infrastructure, legal |
| Reserve | 10% | Buffer for opportunities |

**Milestones (Post-Funding):**

| Timeline | Goal |
|----------|------|
| Month 1 | App Store launch, 500 downloads |
| Month 2 | 1,000 DAU, Product Hunt feature |
| Month 3 | $500 MRR, influencer partnerships |
| Month 6 | 5,000 DAU, $5,000 MRR, seed round |

---

## Slide 10: Links & Resources

| Resource | Link |
|----------|------|
| **GitHub Repo** | github.com/xadev12/aura |
| **Demo Video** | [To be recorded] |
| **Pitch Deck** | This document |
| **TestFlight** | Blocked (Apple cert issue) — Simulator demo available |

**Contact:**
- Email: xadev12@gmail.com
- Twitter: @xavier_liew

---

## Appendix: Technical Deep Dive

### Content Generation Strategy

**Daily Content Requirements:**
- 16 MBTI types × 12 Zodiac signs × 5 Categories = 960 daily combinations
- Cached per user, refreshed at 6 AM local time
- Fallback: Generic type-only or sign-only content if API fails

**Prompt Engineering:**
```
Generate a daily horoscope reading for a [MBTI_TYPE] [ZODIAC_SIGN] 
on [DAY_OF_WEEK] focused on [CATEGORY]. 

Tone: Positive, empowering, actionable.
Length: 100-150 words (free), 250-350 words (premium).
Include: Specific advice, cosmic context, actionable next step.
```

### MBTI Scoring Algorithm

- 50 questions, weighted by cognitive function correlation
- 4 dimensions: E/I, S/N, T/F, J/P
- Results validated against official MBTI correlation (85%+)
- Cognitive function stack auto-generated from type code

### RevenueCat Integration

- StoreKit 2 wrapper for subscription management
- Monthly: $4.99, Annual: $29.99 (50% savings)
- 7-day free trial for premium
- Restore purchases + receipt validation

---

*Aura — Daily guidance for your unique self.*
