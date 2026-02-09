# Technical Specification Review: Aura (Horoscope/MBTI App)

**Project:** horoscope-app  
**Stage:** spec_review  
**Date:** 2026-02-07  
**Status:** ✅ **APPROVE with NOTES**

---

## Overall Assessment

**Verdict:** The technical specification is comprehensive and well-architected. Clean Architecture + MVVM is appropriate for this scope. The local-first approach with Supabase sync is a smart choice for offline support. Minor concerns around OpenAI dependency and cost management.

**Risk Level:** MEDIUM (primarily due to external API dependencies)

---

## 1. Architecture Review ✅

### Strengths
- **Clean Architecture + MVVM:** Clear separation of concerns, testable
- **Local-first with SwiftData:** Good offline support, fast local reads
- **Repository pattern:** Abstracts data sources, enables testing
- **Dependency injection:** Container-based DI supports testing

### Concerns
| Issue | Severity | Note |
|-------|----------|------|
| Dual sync strategy | Medium | SwiftData ↔ Supabase sync logic needs careful conflict handling |
| State management | Low | @Observable requires iOS 17+, limits device support |

**Recommendation:** Document conflict resolution strategy for edge cases (same reading modified offline on two devices).

---

## 2. Data Models ✅

### Strengths
- Well-structured SwiftData entities with proper relationships
- Appropriate use of @Attribute(.unique) for IDs
- JSONB for flexible MBTI dimension scores
- Proper DELETE CASCADE on relationships

### Key Concerns

**2.1 DailyReading Content Size**
- Premium: 250-350 words
- Free: 100-150 words
- Stored as TEXT in database
- **Concern:** No content length validation at DB level

**Recommendation:** Add CHECK constraint or app-level validation to prevent oversized content.

**2.2 Fortune Score Determinism**
```swift
fortuneScore = Int.random(in: 60...95) // Random generation
```
- Same user, same day, different launches = different scores
- **Concern:** Inconsistent user experience

**Recommendation:** Use hash-based generation from userId + date + zodiac for deterministic but seemingly random scores.

---

## 3. API Design ⚠️

### 3.1 OpenAI Integration (CRITICAL CONCERN)

**Current Implementation:**
- Model: `gpt-4o-mini`
- Max tokens: 500 (premium), 200 (free)
- No caching layer mentioned
- No rate limiting per user

**Cost Projection:**
| Scenario | Daily Cost |
|----------|------------|
| 1000 free users (1 reading/day) | ~$2-4/day |
| 1000 premium users (5 readings/day) | ~$10-20/day |
| 10,000 users mixed | ~$100-200/day |

**Recommendations:**
1. **Add response caching** — Cache readings by (zodiac + mbti + category + date) for 24 hours
2. **Implement rate limiting** — Max 1 generation per category per day per user
3. **Pre-generate popular combinations** — Cron job to generate top 20 zodiac/mbti combos daily
4. **Fallback content** — Have template-based fallback if OpenAI fails/rate-limits

### 3.2 Edge Function Security

**Current:** Direct OpenAI API key in Edge Function environment
```typescript
const openai = new OpenAI({ apiKey: Deno.env.get('OPENAI_API_KEY') })
```

**Concern:** No user-specific rate limiting in the function

**Recommendation:** Add per-user rate limiting:
```typescript
const { data: limit } = await supabase.rpc('check_rate_limit', { user_id: userId })
if (!limit.allowed) return new Response('Rate limited', { status: 429 })
```

### 3.3 API Response Times

**Edge Cases:**
- OpenAI cold start: +2-5 seconds
- Edge function cold start: +500ms
- Total potential delay: 5-8 seconds

**Recommendation:** Show loading state immediately, stream response if possible.

---

## 4. UI Components ✅

### Strengths
- Component breakdown is clear
- Animation considerations included (fortune score count-up)
- Premium paywall designed with feature gating

### Concerns

**4.1 ReadingCard Line Limit**
```swift
.lineLimit(isExpanded ? nil : 4)
```
- 4 lines may not give enough preview
- **Recommendation:** A/B test 4 vs 6 lines

**4.2 Category Selector Horizontal Scroll**
- May not indicate scrollability on first view
- **Recommendation:** Add visual indicator or default to first 3 visible

---

## 5. State Management ✅

### Strengths
- @Observable for modern SwiftUI
- ViewModels isolated per screen
- AppState for global state

### Concern: SwiftData Concurrency

```swift
@Observable
final class TodayViewModel {
    // Accessing SwiftData from async context
    func loadReading() async {
        // This runs on background actor by default
        currentReading = try await readingRepository.generate(...)
    }
}
```

**Issue:** SwiftData contexts are actor-isolated. Ensure repository handles actor isolation properly.

**Recommendation:** 
```swift
// In Repository
func generate(user: UserProfile, category: SituationCategory) async throws -> DailyReading {
    await MainActor.run {
        // SwiftData operations on MainActor
    }
}
```

---

## 6. Database Schema ✅

### Strengths
- Proper indexes on foreign keys
- RLS policies implemented
- CHECK constraints on enums
- JSONB for flexible data

### Recommendations

**6.1 Add Content Versioning**
```sql
ALTER TABLE daily_readings ADD COLUMN content_version INTEGER DEFAULT 1;
```
For future content regeneration without losing user interactions.

**6.2 Add Analytics Columns**
```sql
ALTER TABLE daily_readings ADD COLUMN view_count INTEGER DEFAULT 0;
ALTER TABLE daily_readings ADD COLUMN shared BOOLEAN DEFAULT FALSE;
```

---

## 7. Authentication ⚠️

### Concern: Local-First Sync Race Condition

```swift
// 1. Create local profile
let profile = UserProfile(...)
modelContext.insert(profile)
try modelContext.save()

// 2. Sync to Supabase
try await syncUserToSupabase(profile) // May fail

// 3. RevenueCat identify
Purchases.shared.logIn(user.id.uuidString)
```

**Issue:** If step 2 fails, user has local profile but no cloud sync. Subsequent logins may create duplicate profiles.

**Recommendation:** Implement retry logic and conflict resolution:
```swift
func syncWithRetry(profile: UserProfile, attempts: Int = 3) async throws {
    for attempt in 1...attempts {
        do {
            try await syncUserToSupabase(profile)
            return
        } catch {
            if attempt == attempts { throw error }
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
        }
    }
}
```

---

## 8. RevenueCat Integration ✅

### Strengths
- Proper delegate implementation
- Purchase restoration included
- Loading states handled

### Missing: Server-Side Validation

**Current:** Client-side only entitlement check
**Concern:** Client can be bypassed

**Recommendation:** Add webhook endpoint for RevenueCat to sync subscription status to Supabase:
```typescript
// supabase/functions/revenuecat-webhook/index.ts
serve(async (req) => {
  const event = await req.json()
  // Update subscriptions table from RevenueCat webhook
})
```

---

## 9. Testing Strategy ✅

### Coverage Assessment
| Type | Coverage | Status |
|------|----------|--------|
| Unit tests | Models, Calculators | ✅ Good |
| UI tests | Onboarding flow | ✅ Good |
| Integration tests | Sync logic | ✅ Good |
| E2E tests | Full user journey | ⚠️ Missing |

**Recommendation:** Add E2E test for:
1. Sign up → Complete onboarding → Get reading → Upgrade to premium

---

## 10. Deployment Plan ✅

### Strengths
- Multi-environment setup
- CI/CD pipeline defined
- Secrets management via build settings

### Critical: Pre-Launch API Load Test

**Test Scenario:**
- 1000 concurrent users
- All request readings at same time (9 AM)
- OpenAI rate limit: 500 RPM for mini

**Likely Outcome:** Rate limiting kicks in, users see errors

**Mitigation:**
1. Implement request queue with backoff
2. Pre-generate readings for all zodiac/mbti combos at midnight
3. Use OpenAI batch API for pre-generation

---

## 11. Security ✅

### Strengths
- RLS policies in place
- No hardcoded secrets
- HTTPS enforcement mentioned

### Recommendation: Content Filtering

Add moderation layer for AI-generated content:
```typescript
// After OpenAI response
const flagged = await moderateContent(content)
if (flagged) {
  content = await getFallbackContent(zodiac, mbti, category)
}
```

---

## 12. Performance Targets ✅

### Assessment
| Target | Feasibility | Note |
|--------|-------------|------|
| App launch < 2s | ✅ Achievable | SwiftData is fast |
| Reading load < 1s | ✅ Achievable | With local cache |
| AI generation < 3s | ⚠️ Variable | Depends on OpenAI load |

**Recommendation:** Add "generation time" metric to PostHog for monitoring.

---

## Summary: Critical Issues to Address

| Priority | Issue | Action |
|----------|-------|--------|
| 🔴 HIGH | OpenAI cost scaling | Implement caching + rate limiting |
| 🔴 HIGH | OpenAI rate limits at launch | Pre-generate popular combinations |
| 🟡 MEDIUM | Fortune score randomness | Make deterministic by user/date |
| 🟡 MEDIUM | Sync race condition | Add retry logic with conflict resolution |
| 🟢 LOW | Content versioning | Add version column for future regeneration |

---

## Final Verdict

**APPROVE with NOTES**

The specification is solid and implementation-ready. The architecture is appropriate for the scope. Primary concerns are operational (OpenAI costs/rate limits) rather than architectural. Address the HIGH priority items before launch, MEDIUM items in Sprint 2.

**Estimated Implementation:** 4-6 weeks for MVP
**Estimated Monthly Cost at 1K users:** $100-300 (OpenAI)

---

**Reviewed by:** Yuki  
**Date:** 2026-02-07  
**Status:** Ready for implementation with noted concerns
