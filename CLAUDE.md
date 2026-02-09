# CLAUDE.md - Horoscope/MBTI App (Aura)

## Overview
Aura is an iOS app that combines daily horoscopes with MBTI personality insights. It delivers personalized daily guidance and offers a freemium subscription model.

## Tech Stack
- iOS: SwiftUI
- Local storage/state: SwiftData
- Backend: Supabase (auth, edge functions)
- AI content: OpenAI GPT-4o API
- Payments: RevenueCat (StoreKit)
- Analytics: PostHog

## Key Product Areas
- Onboarding + MBTI assessment
- Daily readings + category filters
- Weekly outlook
- Premium paywall + subscription
- Profile + MBTI deep dive

## Repo Layout
- `prd.md` — Product requirements
- `pipeline.json` — Stage gate status

## Development (planned)
- iOS build: Xcode / SwiftUI
- Backend: Supabase Edge Functions

## Environment Variables (planned)
- OPENAI_API_KEY
- SUPABASE_URL
- SUPABASE_ANON_KEY
- POSTHOG_API_KEY
- REVENUECAT_API_KEY

## Notes
This project is in PRD review stage. Implementation pending tech spec.