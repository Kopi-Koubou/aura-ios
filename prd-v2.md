# Product Requirements Document — v2

## Aura: Daily Personality Horoscope

**Version:** 2.0
**Date:** February 7, 2026
**Target Launch:** April 6, 2026
**Status:** Enhanced Draft (Growth + Revenue Focus)
**Priority:** P1 (Sprint Critical)
**Supersedes:** prd.md v1.0

---

## Executive Summary & Strategic Recommendations

### The Opportunity

The horoscope & astrology app market is valued at ~$1.26B in 2026 (growing 9.3% CAGR), while the online personality test market sits at ~$2.5B. No major app successfully fuses both. Co-Star earns ~$800K/month with 20M+ downloads by doing astrology alone. 16Personalities gets 200M+ annual visitors doing MBTI alone. Aura sits at the intersection — a blue ocean.

### Key Strategic Recommendations

**1. Combined App (MBTI + Horoscope) — Strongly Recommended**

Do NOT split into separate apps. The fusion is the differentiator. Rationale:
- **Unique positioning:** "The only app that knows your stars AND your mind" — no competitor does this
- **Higher perceived value:** Two systems of insight > one, justifying premium pricing
- **Better retention:** MBTI gives depth; horoscopes give daily recurrence. Together they solve both the "one-and-done" problem (16Personalities) and the "too shallow" problem (Co-Star)
- **Lower CAC:** One app to market, one brand to build, one ASO strategy
- **Cross-pollination:** MBTI enthusiasts discover astrology; astrology fans discover MBTI

**2. MBTI Test: Free, Not Paid**

The MBTI test should be free and mandatory (or strongly encouraged) during onboarding. It's the activation hook, not the paywall:
- It creates immediate investment (5-8 minutes of effort = sunk cost = retention)
- It generates the personalization data that makes everything else valuable
- It's the "aha moment" — the first time a user sees their type + zodiac reading, they understand the product
- Gate it behind a paywall and you lose 80%+ of users before they see value
- Monetize what the test *unlocks* (deeper readings, compatibility, etc.), not the test itself

**3. Daily Habit Before Revenue**

Optimize the first 30 days entirely for habit formation. Revenue comes from retention, and retention comes from daily engagement. The sequence is: **Activate → Habit → Monetize**. Pushing paywalls too early kills the flywheel.

**4. Pricing: Premium at $5.99/mo, Introduce Lifetime**

Raise monthly from $4.99 to $5.99. Add a lifetime option at $39.99. The $0.99 increase from v1 is justified by the added MBTI depth. The lifetime option captures users who won't subscribe but will impulse-buy.

### Target Outcomes (Revised)

| Metric | Target | Timeline |
|--------|--------|----------|
| Monthly Revenue | $5,000 | Month 6 |
| Monthly Revenue | $15,000 | Month 12 |
| Daily Active Users | 500 | Month 2 |
| Daily Active Users | 3,000 | Month 6 |
| Free-to-Paid Conversion | 5-8% | Month 6 |
| D7 Retention | 40% | Month 3 |
| D30 Retention | 20% | Month 6 |
| App Store Rating | 4.7+ stars | Ongoing |

---

## 1. Product Vision & Positioning

### Vision

To become the daily self-discovery companion for people who want guidance that actually understands who they are — not generic horoscopes, not one-time personality tests, but a living fusion of cosmic timing and psychological depth.

### Positioning Statement

**For** young adults interested in self-discovery and daily guidance,
**Aura is** a personality-powered horoscope app
**That** combines your MBTI cognitive type with your zodiac sign to deliver readings that feel uncannily personal.
**Unlike** Co-Star (astrology only, often negative), 16Personalities (one-and-done test), or The Pattern (vague, confusing),
**Aura** gives you a meaningful daily ritual that gets smarter the more you use it.

### Competitive Landscape

| App | Strength | Weakness | Aura's Advantage |
|-----|----------|----------|------------------|
| Co-Star | Brand, social features, 20M+ users | Negative tone, no personality depth, text-only design | Warm tone + MBTI personalization |
| The Pattern | AI-powered, celebrity users | Confusing UX, no daily habit, vague language | Clear daily ritual, actionable advice |
| 16Personalities | Best MBTI test, 200M+ visitors | No daily value, one-time visit | Daily engagement via horoscope fusion |
| Sanctuary | Live astrologers, premium feel | Expensive ($20/mo), not scalable | AI-powered at accessible price |
| Headspace | Habit-forming daily use, warm brand | Not astrology/personality space | Borrowed best practices for engagement |

---

## 2. User Personas (Refined)

### Primary: The Daily Seeker — Maya, 26

- **Who:** Urban creative professional, iPhone user, $60K income
- **Current behavior:** Checks Co-Star mornings, has "INFP" in dating profile, follows @astrologymemes
- **Frustration:** "Co-Star told me to 'do nothing today' — that's not helpful." "16Personalities was amazing but I took it once and never went back."
- **What she wants:** A morning ritual that feels like a wise friend who knows her deeply
- **Activation trigger:** Takes the MBTI test, sees her first Pisces-INFP reading, thinks "how does it know me?"
- **Willingness to pay:** $5-6/month for something she uses daily (currently pays for Spotify, not for Co-Star)
- **Viral behavior:** Screenshots her daily reading to Instagram Stories, sends to group chat

### Secondary: The Type Nerd — Ryan, 29

- **Who:** Software engineer, deep into cognitive functions, knows his stack is Ni-Te-Fi-Se
- **Current behavior:** Watches MBTI YouTube channels, reads r/mbti, casually follows astrology
- **Frustration:** "MBTI apps have no daily value. I already know I'm INTJ."
- **What he wants:** Daily application of his type knowledge, compatibility insights with friends/partners
- **Activation trigger:** Sees the cognitive function breakdown paired with daily cosmic energy
- **Willingness to pay:** Will buy lifetime access if convinced of depth
- **Viral behavior:** Shares compatibility results with partner, debates types in group chats

### Tertiary: The Social Sharer — Jess, 22

- **Who:** College senior, personality quiz obsessive, group chat coordinator
- **Current behavior:** Takes every BuzzFeed quiz, shares everything, checks horoscope with friends
- **Frustration:** "Most horoscope apps are boring. I want something fun to talk about with friends."
- **What she wants:** Shareable content, friend compatibility, daily conversation starters
- **Activation trigger:** Sends her type card to 3 friends in first session
- **Willingness to pay:** Won't subscribe, but will do referrals for free features
- **Viral behavior:** Gets entire friend group to download, creates MBTI comparison screenshots

---

## 3. Growth & Engagement Strategy

### 3.1 Daily Habit Formation Framework

Aura's engagement model follows the Hook Model (Trigger → Action → Variable Reward → Investment), adapted ethically for self-discovery:

```
TRIGGER (external)          TRIGGER (internal)
├── Morning notification     ├── "I wonder what today holds"
├── Widget glance            ├── "I need guidance on this decision"
└── Friend's share           └── "What's my energy like today?"
        ↓                            ↓
ACTION (low friction)
├── Open app → today's reading loads instantly
├── Tap widget → reading expands
└── Tap shared link → see friend's type + get yours
        ↓
VARIABLE REWARD
├── New reading every day (novelty)
├── Fortune score (gamification)
├── "Cosmic match" of the day (social)
├── Streak counter with milestones
└── Weekly trend that only reveals on day 7
        ↓
INVESTMENT (increases future value)
├── Reading history builds personal pattern
├── Streak extends (loss aversion)
├── Saved readings become journal
├── Compatibility connections added
└── Personality insights deepen over time
```

### 3.2 The "Seven Hooks" — Daily Engagement Mechanics

Each of these gives a reason to open the app every single day:

| # | Hook | Type | Tier |
|---|------|------|------|
| 1 | **Daily Reading** — fresh personalized horoscope for your type + sign | Content | Free |
| 2 | **Fortune Score** — today's cosmic energy as a percentage (changes daily) | Gamification | Free |
| 3 | **Streak Counter** — consecutive days of checking in, with milestones | Progress | Free |
| 4 | **Daily Affirmation** — one-line mantra based on type + cosmic energy | Micro-content | Free |
| 5 | **Cosmic Match** — "today you vibe best with ENFP Leos" (changes daily) | Social/curiosity | Free |
| 6 | **Weekly Reveal** — full week trend only visible after 7 days of check-ins | Gated reward | Free (earned) |
| 7 | **Mood Check-in** — morning mood → evening reflection → personal patterns over time | Self-tracking | Premium |

### 3.3 Streak & Reward System

Streaks are the single most powerful retention mechanic for daily apps. Design them to feel rewarding, not punishing.

| Streak | Reward | Purpose |
|--------|--------|---------|
| 3 days | "Rising Star" badge + unlock power colors | Early momentum |
| 7 days | Full weekly insight unlocked | First major reward |
| 14 days | Unlock "Cosmic Pattern" — personal trend analysis | Deepen investment |
| 30 days | "Constellation" badge + 1 free premium reading | Celebrate habit |
| 60 days | Unlock detailed cognitive function daily tips | Long-term reward |
| 100 days | "Celestial" status + exclusive profile frame | Identity/status |

**Streak forgiveness:** 1 free "shield" per week (resets missed day). Premium users get 3 shields/week. This prevents rage-quitting after a missed day — the #1 streak killer.

### 3.4 Notification Strategy

Notifications are the external trigger. They must feel valuable, not spammy.

| Notification | Time | Frequency | Copy Style |
|-------------|------|-----------|------------|
| Morning reading | 7:30 AM (configurable) | Daily | "Good morning, Maya. Your Pisces energy is at 87% today — see what the cosmos has for you." |
| Fortune spike | When score > 90% | ~2x/week | "Your cosmic energy is peaking at 94% today. Don't miss this one." |
| Streak at risk | 8 PM if not opened | Only if active streak | "Your 12-day streak is still alive! Quick peek?" |
| Weekly summary | Sunday 10 AM | Weekly | "Your week in the stars: 3 high-energy days, 1 cosmic alignment. See your recap." |
| Retrograde alert | Event-based | ~4x/year | "Mercury retrograde starts tomorrow. Here's what it means for your INTJ mind." |

**Rules:**
- Max 1 notification per day (except streak-at-risk, which is a second)
- User controls all notification types independently
- First week: only morning readings (earn trust before variety)
- Never send notifications between 10 PM and 7 AM

### 3.5 Widgets (Passive Engagement)

iOS widgets are free impressions — the user sees Aura on their home screen dozens of times per day.

| Widget | Size | Content |
|--------|------|---------|
| Fortune Glance | Small (2×2) | Fortune %, zodiac icon, one-word mood |
| Daily Reading | Medium (4×2) | First 2 lines of today's reading + fortune % |
| Weekly Grid | Large (4×4) | 7-day fortune overview with today highlighted |

Widgets update at 6 AM daily. Tapping opens the full reading. Widgets alone can drive 15-20% of daily opens.

### 3.6 Viral & Growth Mechanics

#### Organic Viral Loops

| Mechanic | How It Works | K-Factor Target |
|----------|-------------|-----------------|
| **Share Card** | Beautiful, branded card with reading excerpt + type/sign badge. One-tap share to IG Stories, iMessage, WhatsApp. Card includes "Get your reading" link. | 0.3 |
| **Type Reveal** | After MBTI test, shareable "reveal card" — "I'm an INFP Scorpio. What are you?" | 0.5 |
| **Compatibility Check** | "See how you match with a friend" — requires friend to also have Aura | 0.4 |
| **Duo Reading** | Premium: combined reading for two people (romantic/friendship) — both need the app | 0.3 |

#### Referral Program

| Trigger | Reward (Referrer) | Reward (Referee) | Why It Works |
|---------|-------------------|------------------|--------------|
| Friend downloads + completes onboarding | 3 days of premium access | First day all categories unlocked | Low friction, high perceived value |
| Friend subscribes to premium | 1 month free premium | — | Aligns incentive with monetization |
| 3 friends referred | Exclusive "Cosmic Connector" badge | — | Social status reward |

**Referral UX:** Deep links that pre-fill "Invited by Maya (INFP Pisces)" on the welcome screen. The new user immediately sees a human connection.

#### Content-Led Growth

| Channel | Tactic | Content Type |
|---------|--------|-------------|
| TikTok/Reels | Daily "type of the day" content — "POV: you're an ENTJ during Mercury retrograde" | Short-form video (15-30s) |
| Instagram | Shareable type cards, daily fortune graphics, compatibility grids | Static + carousel |
| Reddit | Authentic participation in r/astrology, r/mbti — link to app when relevant | Community |
| Twitter/X | Daily one-liner horoscopes tagged by type + sign | Text posts |
| Product Hunt | Launch day campaign with "first 500 users get lifetime premium" | Launch event |

#### App Store Optimization

| Element | v1 | v2 (Enhanced) |
|---------|-----|---------------|
| App Name | Aura: Horoscope & Personality | **Aura: Horoscope × MBTI** |
| Subtitle | Daily guidance for your unique self | **Daily readings powered by your personality type** |
| Keywords | horoscope, MBTI, astrology, personality, daily, zodiac | + compatibility, cognitive functions, fortune, daily ritual, personality test |
| Screenshots | 5 standard screens | 6 screens: Type Reveal moment, Today reading, Fortune score, Compatibility, Streak achievement, Share card |
| Preview Video | 15-30s core flow | **30s: test → reveal → "whoa" reaction → daily reading → share** |

---

## 4. Revenue Optimization

### 4.1 Pricing Architecture

#### Three-Tier Model

| Tier | Price | Billing | Value Prop |
|------|-------|---------|------------|
| **Free** | $0 | — | Daily reading (1 category), MBTI test, fortune score, streak tracking, share cards |
| **Premium** | $5.99/mo | Monthly | All categories, extended readings, weekly forecast, mood tracking, compatibility, 3 streak shields/week |
| **Premium** | $34.99/yr | Annual (51% off) | Same as monthly, promoted as best value |
| **Lifetime** | $39.99 | One-time | Full premium forever. Limited "founding member" pricing (increases to $59.99 after first 1000 purchases) |

#### Pricing Psychology

- **$5.99/mo** is the "one fancy coffee" anchor — the most common mental model for app pricing
- **$34.99/yr** emphasizes "saves you $37/year" vs monthly — annual is always the goal
- **$39.99 lifetime** captures the "I don't do subscriptions" segment (~15-20% of users). At scale, lifetime users still generate positive LTV because their word-of-mouth value exceeds the one-time revenue loss. The "founding member" urgency drives early conversions
- **7-day free trial** on annual plan only — this forces users to consider the annual option first
- Annual should be the default selected option on the paywall, with monthly shown as the "expensive" alternative

### 4.2 Free vs. Paid Feature Matrix

The free tier must be genuinely useful for daily engagement. The premium tier must feel like an obvious upgrade, not a ransom.

**Principle: Free = daily habit. Premium = daily delight.**

| Feature | Free | Premium | Rationale |
|---------|------|---------|-----------|
| Daily reading | 1 category (user chooses) | All 5 categories | Free users still get real value every day |
| Reading length | ~120 words | ~300 words (deeper, with actionable steps) | Premium reads feel noticeably richer |
| MBTI test | Full test + basic result | Full test + detailed cognitive function profile | Test is the hook — never gate it |
| Fortune score | Full (0-100%) | Full + lucky numbers, power colors, compatible signs | Score is the daily dopamine; extras are premium |
| Streak tracking | Full | Full + 3 shields/week (vs 1) | Streaks drive retention; shields drive upgrades |
| Weekly forecast | Locked (teaser visible) | Full 7-day outlook | #1 conversion driver — users see the locked content daily |
| Mood tracking | Not available | Morning + evening check-in with trend analysis | Premium-only self-growth feature |
| Compatibility | Basic (1 comparison) | Unlimited comparisons + detailed breakdown | Social feature drives upgrades |
| Historical readings | Last 3 days | Unlimited archive + search | Light gate, not aggressive |
| Monthly trends | Not available | In-depth monthly cosmic analysis | Premium depth content |
| Retrograde alerts | Not available | Push notifications + guidance | Premium awareness |
| Share cards | Basic (reading excerpt) | Premium cards with custom themes | Free shares still drive virality |
| Daily affirmation | Available | Available | Universal goodwill |
| Duo readings | Not available | Combined reading for 2 people | Premium social feature |
| Ad-free | Small, tasteful banner on weekly tab | Fully ad-free | Ads only in one place — never disruptive |

### 4.3 Conversion Strategy — The Paywall Journey

The paywall should never feel like a wall. It should feel like a door to a room you've been peeking into.

#### Conversion Triggers (When to Show the Paywall)

| Trigger | Context | Conversion Potential |
|---------|---------|---------------------|
| Tap locked category | User wants to read Love but only Career is free today | High — clear desire |
| View weekly forecast teaser | User sees "Your week looks interesting..." with blur | High — curiosity |
| Check compatibility (2nd time) | First comparison free, second requires premium | Medium — social investment |
| Hit 7-day streak | Celebration screen → "Unlock even more with premium" | Medium — positive emotion |
| After MBTI deep dive | User exploring cognitive functions → some locked | Medium — invested in learning |
| Settings → Subscription | User actively looking | Very high — intent |

#### Paywall Design

```
┌─────────────────────────────────────┐
│                                     │
│         Unlock Your Full            │
│          Cosmic Profile             │
│                                     │
│   ✦ All 5 daily categories          │
│   ✦ Extended, deeper readings       │
│   ✦ Weekly & monthly forecasts      │
│   ✦ Unlimited compatibility         │
│   ✦ Mood tracking & insights        │
│   ✦ Streak shields (never lose it)  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  ★ BEST VALUE                 │  │
│  │  Annual — $34.99/year         │  │
│  │  $2.92/mo · Save 51%         │  │
│  │  7-day free trial             │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  Monthly — $5.99/month        │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  Lifetime — $39.99 once       │  │
│  │  ✦ Founding Member Price      │  │
│  └───────────────────────────────┘  │
│                                     │
│         [ Continue Free ]           │
│                                     │
│  Restore Purchases · Terms · Privacy│
└─────────────────────────────────────┘
```

**Key paywall principles:**
- Always show "Continue Free" — never trap the user
- Annual is pre-selected and visually emphasized
- Lifetime has urgency ("Founding Member Price")
- Feature list uses benefit language, not feature names
- Never show paywall before the user has had their first "aha moment" (first reading after onboarding)

### 4.4 Revenue Projections

**Conservative model (Month 6):**

| Metric | Value |
|--------|-------|
| MAU | 6,000 |
| DAU | 1,800 (30% DAU/MAU) |
| Free-to-trial conversion | 12% |
| Trial-to-paid conversion | 45% |
| Net paid conversion | 5.4% |
| Paid users | 324 |
| Monthly subscribers (30%) | 97 × $5.99 = $581 |
| Annual subscribers (50%) | 162 × $2.92/mo = $473 |
| Lifetime purchases (20%) | 65 × $39.99 = $2,600 (one-time, amortized) |
| **Estimated MRR** | **~$3,700** |

**Optimistic model (Month 6, with viral loops working):**

| Metric | Value |
|--------|-------|
| MAU | 15,000 |
| DAU | 5,250 (35% DAU/MAU) |
| Net paid conversion | 6% |
| Paid users | 900 |
| **Estimated MRR** | **~$5,400+** |

**Month 12 target:** $15K MRR requires ~45,000 MAU at 5% conversion, or ~25,000 MAU at 8% conversion. Achievable with strong viral loops and Apple Search Ads.

### 4.5 Cost Structure

| Cost | Monthly (Month 6) | Notes |
|------|--------------------|-------|
| OpenAI API | $150-300 | Aggressive caching (70-90% hit rate) |
| Supabase | $25 | Pro plan |
| RevenueCat | Free | Free under $2.5K MRR, then 1% |
| PostHog | Free | Free tier sufficient to 1M events |
| Apple (30% cut) | ~$1,100 | On all revenue |
| Apple Search Ads | $300 | User acquisition |
| Micro-influencers | $200 | 2-3 per month |
| **Total Cost** | **~$2,075** |
| **Net Revenue** | **~$1,625 - $3,325** |

---

## 5. Onboarding — Maximizing Activation Rate

Onboarding is the single highest-leverage screen in the app. The goal: get every user to their first personalized reading in under 3 minutes.

### 5.1 Onboarding Flow (Revised)

```
Screen 1: Welcome
├── "Discover what the stars say about YOU"
├── Beautiful illustration (warm, cosmic, not generic)
├── [Get Started] button
└── No sign-up required yet (reduce friction)
    ↓
Screen 2: Name + Birthday
├── "What should we call you?" (name field, auto-focused)
├── "When were you born?" (date picker — month/day focus, year optional)
├── Zodiac sign appears with smooth animation as date is entered
├── "You're a Pisces ♓" — immediate personalization
└── [Continue]
    ↓
Screen 3: MBTI Path
├── "Do you know your personality type?"
├── [I know my type] → Type selector grid (4×4)
├── [Take the test] → MBTI Assessment
├── [Skip for now] → Default to balanced type, unlock test later
└── Skip is fine — don't force it. Prompt again after 3 days.
    ↓
Screen 3a: MBTI Assessment (if chosen)
├── 40 questions (reduced from 50 — completion rate matters more than marginal accuracy)
├── Progress bar with encouraging copy at milestones
│   ├── 25%: "You're doing great, keep going"
│   ├── 50%: "Halfway there — your type is forming"
│   ├── 75%: "Almost there — one dimension left"
│   └── 100%: "Done! Let's see who you really are..."
├── Questions presented as relatable scenarios, not abstract
├── Back button available (don't trap users)
├── Estimated time shown: "~5 minutes"
└── Results reveal with animation
    ↓
Screen 4: Type Reveal (THE MOMENT)
├── Full-screen, cinematic reveal
├── Zodiac sign + MBTI type shown together for first time
│   └── "You're a Pisces INFP — The Dreaming Poet"
├── 3-4 bullet points that feel eerily accurate
├── Shareable card auto-generated → [Share Your Type] prominent button
├── This is the #1 viral moment — make it screenshot-worthy
└── [See Your First Reading →]
    ↓
Screen 5: First Reading
├── Today's personalized reading loads immediately
├── Full reading (not gated — first impression matters)
├── Fortune score with animation
├── "This reading was crafted for Pisces INFPs on a Friday"
└── [Explore the App] → Main app with tab bar
    ↓
Screen 6: Soft Permissions
├── "Get your reading every morning?" → Notification permission
├── Only ask AFTER value has been demonstrated
├── If declined, remind in Settings later
└── Never ask for notifications before the first reading
```

### 5.2 Activation Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Onboarding start → complete | 75% | Funnel analytics |
| MBTI test start → complete | 80% | Within test flow |
| First reading viewed | 90% of completed onboards | Event tracking |
| Notification permission granted | 55% | iOS prompt |
| Share card sent (Day 1) | 15% | Share event |
| Return Day 2 | 50% | Retention |

### 5.3 MBTI Assessment Design (Revised)

**Question count:** 40 (reduced from 50)
- Research shows diminishing returns past 40 questions for 4-dimension typing
- Every additional question loses ~2% of test-takers
- 40 questions × 10 per dimension = still high accuracy

**Question format:** Scenario-based, not agree/disagree
```
Example:
"Your friend cancels plans last minute. You..."
  A) Feel relieved — you secretly wanted to stay in anyway
  B) Feel disappointed but text another friend to hang out
  C) Depends on the activity we had planned

vs. (bad — too abstract)
"I prefer spending time alone rather than in groups"
  Strongly Agree / Agree / Neutral / Disagree / Strongly Disagree
```

**Adaptive difficulty:** Questions get more nuanced as the test progresses, narrowing in on borderline dimensions.

---

## 6. Feature Specifications (Enhanced)

### 6.1 Daily Reading Engine

| Attribute | Specification |
|-----------|---------------|
| Content source | OpenAI GPT-4o via Supabase Edge Functions |
| Personalization inputs | Zodiac sign × MBTI type × Day of week × Category × Current planetary transits |
| Update frequency | Batch-generated at 4 AM UTC, cached per user segment |
| Categories | Career, Love, Social, Health, Personal Growth |
| Free content length | 100-150 words — one insight, one actionable step |
| Premium content length | 250-350 words — deeper context, cognitive function angle, ritual suggestion |
| Tone | Warm, empowering, specific, actionable — never vague, never negative |
| Fallback | Pre-written readings per zodiac × MBTI bucket (48 combinations: 12 signs × 4 temperaments) |

**Content quality rules:**
- Every reading must include at least one specific, actionable suggestion
- Never use filler phrases ("the stars align", "cosmic energy flows")
- Reference the user's cognitive functions naturally ("Your Fi is strong today — trust your values")
- End premium readings with a mini-ritual or journaling prompt

### 6.2 Fortune System

| Attribute | Specification |
|-----------|---------------|
| Score range | 0-100% |
| Generation method | Deterministic hash (user ID + date + zodiac element + MBTI temperament) |
| Distribution | Normal distribution centered at 65%, range 35-98% (never below 35 — avoid discouragement) |
| Lucky numbers | 3 numbers (free) / 5 numbers (premium), deterministic per day |
| Power colors | 2 colors (premium), derived from zodiac element + lunar phase |
| Compatible signs | Top 3 signs for today (premium), based on elemental harmony + day energy |

### 6.3 Compatibility Engine (New)

| Attribute | Specification |
|-----------|---------------|
| Input | Two user profiles (zodiac + MBTI) |
| Output | Overall score (0-100%), breakdown by dimension (romantic, friendship, work, growth) |
| Algorithm | Weighted composite of zodiac element harmony (30%), MBTI cognitive function compatibility (50%), daily cosmic modifier (20%) |
| Free tier | 1 comparison per day, basic overall score only |
| Premium tier | Unlimited comparisons, full dimensional breakdown, daily compatibility tips |
| Social hook | "Invite [name] to see your full compatibility" → deep link |

### 6.4 Mood Tracking (Premium)

| Attribute | Specification |
|-----------|---------------|
| Morning check-in | 5 mood options (emoji-based): Energized, Calm, Anxious, Sad, Neutral |
| Evening reflection | "How did your day match your reading?" — 3 options: Spot on / Somewhat / Not today |
| Trend analysis | After 7 days: "Your Tuesdays tend to be your highest energy days" |
| Cosmic correlation | After 14 days: correlate mood patterns with fortune scores and planetary data |
| Journal prompt | Optional — one sentence daily reflection, stored locally |

### 6.5 Weekly & Monthly Content

| Content | Availability | Details |
|---------|-------------|---------|
| Weekly forecast | Premium (teaser visible to free) | 7-day overview with energy curve graph, key days highlighted |
| Monthly trends | Premium | In-depth analysis of monthly planetary movements and their MBTI-specific impact |
| Retrograde guides | Premium (alert free) | Detailed guidance for Mercury/Venus/Mars retrogrades tailored to type |
| Seasonal insights | Premium | Quarterly deep-dive on cosmic seasons and personality patterns |

### 6.6 Profile & Type Exploration

| Feature | Details |
|---------|---------|
| Type profile | Full MBTI type description with cognitive function stack visualization |
| Zodiac profile | Sign overview with element, modality, ruling planet, key dates |
| Combined profile | "The Pisces INFP" — unique narrative combining both systems |
| Cognitive functions | Interactive stack diagram: dominant → auxiliary → tertiary → inferior |
| Growth areas | Based on inferior function + zodiac shadow traits |
| Famous people | Celebrities/figures with same type + sign combination |
| Type evolution | Over time: "Your readings suggest your Fe is developing" (based on mood/feedback data) |

---

## 7. UX/UI Guidelines

### 7.1 Design Philosophy

**Core feeling:** Opening Aura should feel like wrapping yourself in a warm blanket on a cool morning. It's comforting, personal, and gently illuminating — not clinical, not mystical-woo, not cold-tech.

**Design references:**
- **Apple Fitness+** — warm gradients, celebration animations, personal progress
- **Headspace** — friendly illustrations, calming palette, approachable personality
- **FOMO app** — warm tones, modern type, premium feel without pretension
- **Fitbod** — clean data visualization, dark mode done right

**Anti-references (what to avoid):**
- **Co-Star** — too stark, too cold, too text-heavy
- **Generic astrology apps** — gaudy gradients, gold/purple clichés, clip art zodiac symbols
- **Corporate wellness** — sterile, blue, soulless

### 7.2 Color System (Revised)

The palette moves away from pure purple-pink toward warmer, more inviting tones.

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| Background | `#FFFBF5` (warm cream) | `#0F0D13` (deep cosmic) | App background |
| Surface | `#F5F0EA` (soft linen) | `#1A1720` (muted plum) | Cards, sheets |
| Primary | `#7C5CFC` (warm violet) | `#A78BFA` (soft violet) | Buttons, key actions |
| Secondary | `#E8785E` (warm coral) | `#F09B7D` (soft coral) | Highlights, fortune |
| Accent | `#D4A76A` (warm gold) | `#E5C088` (soft gold) | Premium badges, streaks |
| Success | `#5BB98B` (sage green) | `#7BCDA0` (mint) | Positive states |
| Text Primary | `#1F1A2E` (deep indigo) | `#F5F0EA` (cream) | Headlines |
| Text Secondary | `#6B6178` (muted purple) | `#9B93A8` (lavender gray) | Body text |
| Text Tertiary | `#A099AB` (light purple) | `#6B6178` (muted) | Captions, hints |

#### Element Colors (for zodiac)

| Element | Color | Usage |
|---------|-------|-------|
| Fire (Aries, Leo, Sag) | `#E8785E` (coral) | Element accents, backgrounds |
| Earth (Taurus, Virgo, Cap) | `#8B9E6B` (sage) | Element accents, backgrounds |
| Air (Gemini, Libra, Aqua) | `#7CA5C4` (sky) | Element accents, backgrounds |
| Water (Cancer, Scorpio, Pisces) | `#7C7CC4` (periwinkle) | Element accents, backgrounds |

### 7.3 Typography

| Style | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| Display | SF Pro Rounded | 32pt | Bold | Type reveal, celebration moments |
| H1 | SF Pro Display | 28pt | Bold | Screen titles |
| H2 | SF Pro Display | 22pt | Semibold | Section headers |
| H3 | SF Pro Text | 18pt | Semibold | Card headers |
| Body | SF Pro Text | 16pt | Regular | Reading content |
| Body Small | SF Pro Text | 14pt | Regular | Secondary info |
| Caption | SF Pro Text | 12pt | Medium | Labels, timestamps |
| Mono | SF Mono | 14pt | Medium | Fortune numbers, scores |

### 7.4 Iconography

- **Zodiac signs:** Custom-designed, minimal line icons — warm and modern, not clip-art
- **MBTI types:** Abstract geometric symbols representing each type's cognitive vibe
- **UI icons:** SF Symbols where possible, custom where personality matters
- **Style:** 2px stroke, rounded caps, consistent optical weight

### 7.5 Component Library

#### Reading Card
```
┌─────────────────────────────────────┐
│  ♓  Pisces × INFP                  │
│  The Dreaming Poet                  │
│                                     │
│  Your imagination is your           │
│  superpower today. That creative    │
│  idea you've been sitting on?       │
│  Your Fi is giving you the green    │
│  light — trust your values and      │
│  start building...                  │
│                                     │
│  ─── Today's Energy ───            │
│  ████████████████░░░░░  78%        │
│                                     │
│  ♥ Save    ↗ Share    ··· More     │
└─────────────────────────────────────┘

- Card: Surface color, 16pt corner radius, subtle shadow
- Top: zodiac icon + type badge
- Body: reading text in Body font
- Bottom: fortune score bar + action row
- Tap "Share" → generates branded share card
```

#### Fortune Card
```
┌─────────────────────────────────────┐
│          ✦ Today's Fortune ✦        │
│                                     │
│              78%                    │
│     ████████████████░░░░░          │
│                                     │
│  Lucky Numbers    Power Colors      │
│    7  14  23       ● ●             │
│                   Violet  Coral     │
│                                     │
│  Best Match Today                   │
│  ENFP Leo ☀️                        │
│                                     │
│  🔒 Unlock full fortune details     │
└─────────────────────────────────────┘

- Free: score only, rest blurred/locked
- Premium: full card revealed
- Lock row is a soft paywall touchpoint
```

#### Share Card (Viral Asset)
```
┌─────────────────────────────────────┐
│                                     │
│           AURA ✦                    │
│                                     │
│    ♓ Pisces × INFP                 │
│    "Your imagination is your        │
│     superpower today."              │
│                                     │
│    Fortune: 78% ████████░░          │
│                                     │
│    ─────────────────────            │
│    Get your daily reading           │
│    aura.app/get                     │
│                                     │
└─────────────────────────────────────┘

- Designed for Instagram Stories (9:16)
- Also works as iMessage/WhatsApp preview
- Branded but not obnoxious
- User's reading + type visible = social proof
- QR code or short link at bottom
```

### 7.6 Animations & Micro-interactions

| Interaction | Animation | Duration | Feel |
|-------------|-----------|----------|------|
| App launch | Warm fade-in with zodiac constellation | 600ms | Calming entry |
| Reading load | Text appears line by line (typewriter) | 400ms | Like it's being written for you |
| Fortune reveal | Number counts up from 0 + bar fills | 800ms | Anticipation, slot-machine energy |
| Streak milestone | Confetti + badge animation | 1200ms | Celebration |
| Type reveal (onboarding) | 4 letters appear one by one, then morph into full name | 1500ms | Cinematic moment |
| Category switch | Content cross-fades, card subtly morphs | 250ms | Smooth, not jarring |
| Share card generate | Card "prints" from top to bottom | 500ms | Tangible, like receiving a card |
| Pull to refresh | Custom zodiac constellation spinner | 1000ms | Branded, delightful |
| Paywall present | Content pushes down, modal rises from bottom | 300ms | Not blocking — inviting |
| Streak shield used | Shield icon cracks + disappears | 400ms | Felt cost — use wisely |

### 7.7 Dark Mode

Dark mode is the default. The cosmic/celestial theme naturally fits dark backgrounds. Light mode is available for daytime use but dark is the hero experience.

- **Dark mode background:** Deep cosmic indigo (`#0F0D13`), not pure black
- **Cards:** Slightly lighter (`#1A1720`) with 1px border (`#2A2635`) for depth
- **Text contrast:** Minimum 4.5:1 ratio for accessibility
- **Gradients:** Subtle, warm — avoid neon or harsh color transitions
- **Stars:** Tiny particle effect on main background (subtle, not distracting)

---

## 8. Implementation Phases

### Phase 0: Pre-Launch Setup (Week 0 — Current)

- [x] PRD v1 complete
- [x] Tech spec complete
- [x] Core implementation (Swift package)
- [x] QA pass (CRIT-001 through CRIT-003 resolved)
- [ ] PRD v2 enhancements (this document)
- [ ] Design system assets (Figma or direct SwiftUI)

### Phase 1: Core Experience (Weeks 1-2) — "The Daily Ritual"

**Goal:** Ship a version that makes one user check every morning.

| Task | Priority | Effort |
|------|----------|--------|
| Onboarding flow (name, birthday, zodiac reveal) | P0 | 2 days |
| MBTI assessment (40 questions, scenario-based) | P0 | 3 days |
| Type reveal screen (cinematic, shareable) | P0 | 1 day |
| Daily reading screen (1 free category) | P0 | 2 days |
| Fortune score with animated reveal | P0 | 1 day |
| OpenAI content generation + caching | P0 | 2 days |
| Streak counter (basic — consecutive days) | P1 | 0.5 day |
| Daily affirmation | P1 | 0.5 day |

**Exit criteria:** A user can onboard, take the MBTI test, and see a personalized daily reading with fortune score. Feels complete and polished.

### Phase 2: Engagement & Polish (Weeks 3-4) — "The Hooks"

**Goal:** Give users multiple reasons to come back every day.

| Task | Priority | Effort |
|------|----------|--------|
| All 5 category chips (free: 1/day, premium: all) | P0 | 1 day |
| Weekly forecast (premium, teaser for free) | P0 | 2 days |
| Streak milestones + rewards (badges, unlocks) | P0 | 1.5 days |
| Streak shields | P1 | 0.5 day |
| Share card generation (viral asset) | P0 | 2 days |
| iOS widgets (small + medium) | P1 | 2 days |
| Push notifications (morning reading, streak) | P0 | 1 day |
| Profile screen (type + zodiac details) | P1 | 1 day |
| Compatibility check (basic — 1 free comparison) | P1 | 2 days |

**Exit criteria:** D7 retention is testable. Users receive morning notifications, maintain streaks, and can share type cards.

### Phase 3: Monetization (Weeks 5-6) — "The Upgrade"

**Goal:** Revenue mechanics live and optimized.

| Task | Priority | Effort |
|------|----------|--------|
| RevenueCat integration (3 tiers: monthly, annual, lifetime) | P0 | 2 days |
| Paywall UI (feature-focused, annual-default) | P0 | 1.5 days |
| Premium content gates (categories, weekly, fortune extras) | P0 | 1 day |
| Extended premium readings (2x length, cognitive function angle) | P0 | 1 day |
| Free trial setup (7-day on annual) | P0 | 0.5 day |
| Historical readings archive (premium) | P1 | 1 day |
| Monthly trends (premium content) | P1 | 1 day |
| Referral system (deep links, reward tracking) | P1 | 2 days |

**Exit criteria:** Users can subscribe, paywall triggers at natural moments, premium content feels noticeably better than free.

### Phase 4: Growth & Virality (Weeks 7-8) — "The Flywheel"

**Goal:** Organic growth mechanics working. Ready for public launch.

| Task | Priority | Effort |
|------|----------|--------|
| Mood tracking (premium) | P1 | 2 days |
| Duo readings (combined compatibility reading) | P1 | 2 days |
| Large widget (weekly grid) | P2 | 1 day |
| Retrograde alerts | P2 | 1 day |
| Cosmic match of the day (daily compatible type) | P1 | 0.5 day |
| App Store assets (screenshots, preview video, description) | P0 | 2 days |
| Analytics event audit (all funnels instrumented) | P0 | 1 day |
| Performance optimization (launch < 2s, reading < 1s) | P0 | 1 day |
| Beta testing (TestFlight, 50 users) | P0 | Ongoing |

**Exit criteria:** App Store submission ready. Beta feedback incorporated. All growth mechanics testable.

### Phase 5: Post-Launch Iteration (Weeks 9+)

| Feature | Priority | Notes |
|---------|----------|-------|
| A/B test paywall designs | P0 | RevenueCat experiments |
| Notification timing optimization | P0 | Based on open rate data |
| Referral program V2 (based on data) | P1 | Optimize reward structure |
| Social features (friend list, shared readings) | P2 | Only if K-factor warrants investment |
| Live readings with astrologer (premium+) | P3 | Potential high-revenue feature |
| Android (React Native or Kotlin) | P2 | Only after iOS proves product-market fit |
| Chinese/Vedic zodiac support | P3 | Market expansion |
| Localization (Spanish, Portuguese, Korean) | P2 | Astrology is globally popular |

---

## 9. Success Metrics (Comprehensive)

### 9.1 North Star Metric

**Daily Active Users who view their reading** — this measures both growth AND engagement in one number.

### 9.2 Funnel Metrics

| Stage | Metric | Target (M3) | Target (M6) | Target (M12) |
|-------|--------|-------------|-------------|--------------|
| **Awareness** | App Store impressions/month | 10,000 | 30,000 | 100,000 |
| **Acquisition** | Downloads/month | 500 | 2,000 | 8,000 |
| **Activation** | Onboarding complete rate | 75% | 78% | 80% |
| **Activation** | MBTI test complete rate | 65% | 70% | 75% |
| **Activation** | First reading viewed | 90% | 92% | 95% |
| **Engagement** | DAU/MAU ratio | 28% | 33% | 38% |
| **Engagement** | Avg sessions/week | 4.5 | 5.5 | 6.0 |
| **Engagement** | Avg streak length (days) | 5 | 8 | 12 |
| **Retention** | D1 retention | 55% | 60% | 65% |
| **Retention** | D7 retention | 35% | 40% | 45% |
| **Retention** | D30 retention | 18% | 22% | 28% |
| **Revenue** | Free-to-trial rate | 10% | 14% | 16% |
| **Revenue** | Trial-to-paid rate | 40% | 48% | 52% |
| **Revenue** | Net paid conversion | 4% | 6.7% | 8.3% |
| **Revenue** | MRR | $1,500 | $5,000 | $15,000 |
| **Virality** | Share rate (% of DAU) | 8% | 12% | 15% |
| **Virality** | K-factor | 0.2 | 0.4 | 0.6 |
| **Virality** | Organic % of installs | 40% | 55% | 65% |

### 9.3 Health Metrics

| Metric | Target | Alert |
|--------|--------|-------|
| App crash rate | < 0.3% | > 0.5% |
| Content load time (cached) | < 1s | > 2s |
| Content load time (generated) | < 3s | > 5s |
| API error rate | < 1% | > 2% |
| Subscription churn (monthly) | < 12% | > 18% |
| Subscription churn (annual) | < 5% | > 8% |
| App Store rating | 4.7+ | < 4.3 |
| Support tickets/week | < 5 | > 10 |
| OpenAI cost per user/month | < $0.10 | > $0.20 |
| Notification opt-in rate | > 55% | < 40% |
| Notification open rate | > 15% | < 8% |

---

## 10. Risks & Mitigations (Updated)

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| OpenAI API costs scale faster than revenue | Medium | High | Batch-generate popular combinations. Cache aggressively (70-90% hit rate). Fallback to pre-written content. Set hard per-user rate limits. |
| Low conversion — users love free, won't pay | Medium | High | A/B test paywall designs. Ensure premium content is visibly better. Test lifetime pricing. Consider ads on free tier (tasteful, one location). |
| Streaks feel punishing, not motivating | Medium | Medium | Streak shields. Never show "streak lost" in negative language — say "start a new streak!" Celebrate comebacks. |
| Competition copies the MBTI × astrology fusion | Medium | Medium | Move fast, build brand loyalty, accumulate user data that competitors can't replicate. Network effects from compatibility features. |
| App Store rejects MBTI claims | Low | High | Use "personality type" language, not "MBTI" trademark. Avoid clinical/diagnostic claims. Frame as entertainment + self-discovery. |
| Content quality varies (AI hallucination) | Medium | Medium | Human review of prompt outputs. Content quality scoring. User feedback loop ("Was this reading helpful?"). Pre-written fallbacks. |
| Notification fatigue → uninstall | Medium | High | Strict max 1/day default. User controls per notification type. A/B test copy and timing. Stop sending after 3 unopened in a row. |
| MBTI accuracy questioned | Low | Medium | Don't claim "official MBTI." Position as "personality type inspired by Jungian cognitive functions." Link to research transparently. |

---

## 11. Open Questions (Resolved + New)

| Question | Status | Decision / Notes |
|----------|--------|-----------------|
| Combined app or separate? | **Resolved** | Combined. MBTI + Horoscope together IS the differentiator. |
| MBTI test free or paid? | **Resolved** | Free. It's the activation hook, not the paywall. |
| Push notification strategy? | **Resolved** | Morning reading (default), streak-at-risk, fortune spike, weekly summary. Max 1/day. |
| Social features? | **Resolved** | Yes, but lightweight. Share cards + compatibility only. No social feed (too complex, not core). |
| Lifetime purchase option? | **Resolved** | Yes, $39.99 "Founding Member" price, increases to $59.99 after 1,000 purchases. |
| Question count for MBTI test? | **Resolved** | 40 (reduced from 50 for completion rate). |
| Chinese zodiac support? | **Deferred** | Phase 5+ feature. Not needed for launch. |
| Android version? | **Deferred** | Only after iOS proves PMF. Consider React Native for speed. |
| Partnership with astrologers? | **Open** | Potential Phase 5 feature — live readings at $X/minute (Astrotalk model generates 90% of their revenue). |
| Ad-supported free tier? | **Open** | Small banner on weekly tab only. Test impact on conversion. May remove if premium conversion is strong enough. |
| Seasonal/event-based content? | **Open** | Valentine's Day compatibility specials, Mercury retrograde guides, etc. High viral potential, needs content pipeline. |

---

## 12. Go-to-Market Timeline

| Week | Milestone | Key Activities |
|------|-----------|---------------|
| W1-2 | Core build | Onboarding, MBTI test, daily reading, fortune |
| W3-4 | Engagement build | Streaks, widgets, notifications, sharing, compatibility |
| W5-6 | Monetization build | RevenueCat, paywall, premium content, referrals |
| W7 | Internal testing | Full app test, analytics audit, performance |
| W8 | Private beta | 50 TestFlight users, feedback collection |
| W9 | Iterate on feedback | Fix issues, optimize flows, A/B test paywall |
| W10 | Public beta | Open TestFlight, Product Hunt submission prep |
| W11 | App Store submission | Submit for review, prep marketing assets |
| W12 | **Launch** (Apr 6) | App Store live, Product Hunt launch, social campaign |
| W13-14 | Post-launch | Monitor metrics, rapid iteration, Apple Search Ads on |
| W15+ | Growth phase | Optimize viral loops, scale spend on working channels |

---

## Appendix A: Content Generation Architecture

### Batch Generation Strategy

Instead of generating content per-user on-demand, batch-generate for all relevant segments:

```
Daily batch (4 AM UTC):
├── 12 zodiac signs × 4 MBTI temperaments × 5 categories = 240 readings
├── 12 zodiac signs × 4 MBTI temperaments × 1 premium extended = 48 premium readings
├── 12 zodiac signs × 1 weekly forecast = 12 weekly forecasts
├── Fortune scores: deterministic hash (no API needed)
└── Total API calls: ~300/day

Cost per day: ~300 calls × ~500 tokens avg × $0.005/1K tokens ≈ $0.75/day ≈ $23/month
```

**MBTI Temperament Buckets:**
- **NT (Analysts):** INTJ, INTP, ENTJ, ENTP
- **NF (Diplomats):** INFJ, INFP, ENFJ, ENFP
- **SJ (Sentinels):** ISTJ, ISFJ, ESTJ, ESFJ
- **SP (Explorers):** ISTP, ISFP, ESTP, ESFP

Using temperament buckets instead of 16 individual types reduces content generation by 4x while maintaining meaningful differentiation. Premium users could get full 16-type specific readings as a future enhancement.

### Prompt Template (v2)

```
System: You are Aura, a warm and insightful guide who combines astrological
wisdom with personality psychology. Your tone is empowering, specific, and
actionable — like a wise friend who truly knows the person.

User: Generate a daily {category} reading for {date} ({day_of_week}).

Audience: {zodiac_sign} with {mbti_temperament} personality traits.

Context:
- Zodiac element: {element}
- Zodiac modality: {modality}
- Current lunar phase: {lunar_phase}
- Notable transits: {planetary_transits}
- Temperament traits: {temperament_description}

Guidelines:
- Length: {word_count} words
- Include one specific, actionable suggestion
- Reference their cognitive preferences naturally (e.g., "your analytical
  nature" for NT, "your empathetic instincts" for NF)
- End with a one-line affirmation
- Tone: warm, confident, personal — never vague or generic
- Do NOT use: "the stars align", "cosmic forces", "universal energy" or
  other filler phrases
- DO reference: specific days, specific actions, specific feelings

Format:
[Reading paragraph(s)]

Today's Affirmation: [One sentence]
```

### Fallback Content Strategy

| Scenario | Fallback | Coverage |
|----------|----------|----------|
| API timeout | Pre-written readings per zodiac × temperament (48 combos × 5 categories = 240) | Full |
| API error | Retry once, then serve previous day's reading with "Yesterday's wisdom still applies" framing | Graceful |
| Rate limit | Queue and serve within 30 seconds | Invisible to user |
| Total API outage | Local-only content from seed bank (updated monthly) | 30 days |

---

## Appendix B: Competitive Pricing Analysis

| App | Free Tier | Paid Tier | Model |
|-----|-----------|-----------|-------|
| Co-Star | Daily horoscope, birth chart | $2.99/mo — compatibility, notifications | Subscription |
| The Pattern | Daily timing, personality | $14.99/mo — in-depth, bond compatibility | Subscription |
| Sanctuary | Daily horoscope | $19.99/mo — live astrologer sessions | Subscription |
| Headspace | 10-day basics | $12.99/mo or $69.99/yr — full library | Subscription |
| Calm | Daily calm, some stories | $14.99/mo or $69.99/yr — full library | Subscription |
| 16Personalities | Full test + basic profile | $36.99 one-time — full profile + ebook | One-time |
| **Aura** | **Daily reading, MBTI test, fortune, streaks** | **$5.99/mo, $34.99/yr, $39.99 lifetime** | **Hybrid** |

Aura is priced above Co-Star (more value) but well below Sanctuary/The Pattern (more accessible). The lifetime option differentiates from all competitors.

---

## Appendix C: MBTI × Zodiac Combination Naming

Every combination gets a unique "archetype name" shown on the type reveal screen and share cards. Examples:

| Sign | NT | NF | SJ | SP |
|------|-----|-----|-----|-----|
| Aries | The Strategic Pioneer | The Passionate Visionary | The Bold Guardian | The Fearless Explorer |
| Taurus | The Patient Architect | The Gentle Dreamer | The Steadfast Protector | The Sensual Artisan |
| Gemini | The Brilliant Analyst | The Curious Idealist | The Versatile Organizer | The Playful Adventurer |
| Cancer | The Deep Strategist | The Empathic Poet | The Nurturing Anchor | The Intuitive Creator |
| Leo | The Commanding Mind | The Radiant Inspirer | The Loyal Leader | The Magnetic Performer |
| Virgo | The Precision Thinker | The Thoughtful Healer | The Meticulous Steward | The Skilled Craftsperson |
| Libra | The Balanced Logician | The Harmonious Mediator | The Fair Arbiter | The Elegant Diplomat |
| Scorpio | The Penetrating Mind | The Transformative Soul | The Resolute Sentinel | The Magnetic Force |
| Sagittarius | The Philosophical Explorer | The Passionate Seeker | The Principled Adventurer | The Boundless Spirit |
| Capricorn | The Master Planner | The Ambitious Dreamer | The Disciplined Builder | The Determined Trailblazer |
| Aquarius | The Visionary Scientist | The Humanitarian Dreamer | The Progressive Guardian | The Unconventional Pioneer |
| Pisces | The Intuitive Theorist | The Dreaming Poet | The Compassionate Keeper | The Mystical Artist |

These archetype names are a key viral asset — users love to discover and share their unique combination.

---

**Document Owner:** Kato
**Last Updated:** February 7, 2026
**Previous Version:** prd.md v1.0
**Next Review:** After Phase 1 implementation begins
