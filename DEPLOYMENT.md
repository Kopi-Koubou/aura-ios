# Aura Backend Deployment Guide

## Overview

This document describes how to deploy the Aura monetization backend to Supabase production.

## Edge Functions

The following edge functions need to be deployed:

| Function | Purpose | Auth Required |
|----------|---------|---------------|
| `referral-redeem` | Referral code redemption with rate limiting | Yes |
| `track-share` | Share tracking with UTM parameters | No (GET), Yes (POST) |
| `generate-horoscope` | Server-side daily reading generation + rate-limit gate + warm-cache API | Mode-based (`GENERATE_HOROSCOPE_AUTH_MODE`) |
| `validate-receipt` | RevenueCat receipt validation | Yes |
| `sync-subscription` | Subscription webhook handler | No (webhook secret) |

## Prerequisites

1. Supabase CLI installed (`brew install supabase`)
2. Access to 1Password Kato vault
3. Supabase project created (production)
4. RevenueCat account with API keys
5. PostHog account (optional, for analytics)
6. Cache warmup secret (`CACHE_WARM_SECRET`) for scheduled pre-generation
7. GitHub repository secrets for workflow automation:
   - `SUPABASE_PROJECT_REF` (required for all backend workflows)
   - `SUPABASE_ANON_KEY` (required for warm-cache and auth-rollout rehearsal workflows)
   - `CACHE_WARM_SECRET` (required for warm-cache workflow)
   - `SUPABASE_SERVICE_ROLE_KEY` (required for readiness workflows and for auth-rollout rehearsal when readiness gates are enabled; also enables dynamic combo selection)
   - Optional: `SUPABASE_BASE_URL`
   - Optional: `AUTH_FALLBACK_ALERT_WEBHOOK_URL` (Slack/Teams-compatible webhook for readiness failures)
   - Optional: `CACHE_DEGRADATION_ALERT_WEBHOOK_URL` (Slack/Teams-compatible webhook for cache degradation readiness failures)
8. Optional auth rollout secret for user-scoped reads:
   - `GENERATE_HOROSCOPE_AUTH_MODE` (`legacy`, `audit`, or `enforce`; defaults to `audit`)
9. Optional rehearsal secrets for automated auth rollout validation (configure one auth source):
   - Static auth source:
     - `AUTH_TEST_BEARER_TOKEN` (JWT for a provisioned staging user)
     - `AUTH_TEST_USER_ID` (UUID for the same staging user)
   - Dynamic auth source (recommended; avoids manual JWT rotation):
     - `AUTH_TEST_USER_EMAIL` (email for a provisioned staging user)
     - `AUTH_TEST_USER_PASSWORD` (password for the same staging user)

## Quick Deploy

### Step 1: Authenticate with Supabase

```bash
supabase login
```

### Step 2: Set Environment Variables

```bash
export SUPABASE_PROJECT_REF="your-project-ref"  # e.g., "aura-prod-xxxxx"
```

### Step 3: Sync + Validate Deploy Parity

```bash
bash ./scripts/sync-deploy-mirrors.sh
bash ./scripts/check-deploy-parity.sh
```

### Step 4: Deploy Functions

```bash
cd /Users/devl/clawd/projects/horoscope-app/aura
./scripts/deploy-functions.sh
```

### Step 5: Set Secrets

```bash
./scripts/set-secrets.sh
```

## Manual Deployment

If you prefer to deploy manually:

### Deploy Individual Functions

```bash
# Link to project
bash ./scripts/sync-deploy-mirrors.sh
bash ./scripts/check-deploy-parity.sh
supabase link --project-ref $SUPABASE_PROJECT_REF

# Deploy each function
supabase functions deploy referral-redeem
supabase functions deploy track-share
supabase functions deploy generate-horoscope
supabase functions deploy validate-receipt
supabase functions deploy sync-subscription
```

### Set Secrets Manually

```bash
# Set required secrets
supabase secrets set SUPABASE_URL="https://your-project.supabase.co"
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
supabase secrets set REVENUECAT_API_KEY="your-revenuecat-api-key"
supabase secrets set REVENUECAT_WEBHOOK_SECRET="your-webhook-secret"
supabase secrets set POSTHOG_API_KEY="your-posthog-key"
supabase secrets set OPENAI_API_KEY="your-openai-api-key"
supabase secrets set CACHE_WARM_SECRET="your-strong-random-secret"
supabase secrets set GENERATE_HOROSCOPE_AUTH_MODE="audit"
```

### Generate Horoscope Auth Mode

`generate-horoscope` supports phased auth enforcement for non-`warm_cache` requests:

- `legacy`: accept `user_id` without JWT (no audit event).
- `audit` (default): accept fallback `user_id`, emit `auth_fallback_accepted` warnings and persist daily fallback counters.
- `enforce`: require `Authorization: Bearer <user-jwt>` for user-scoped requests.

Warm-cache requests remain controlled by `x-cache-warm-secret`.

Before switching to `enforce`, verify both readiness gates:

```bash
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_SERVICE_ROLE_KEY="<supabase-service-role-key>"

# Optional auth readiness overrides:
# export AUTH_READINESS_LOOKBACK_DAYS="3"
# export AUTH_READINESS_MAX_FALLBACKS="0"
# export AUTH_READINESS_CONTEXT_FILTER="all" # all|missing|invalid
#
# Optional cache readiness overrides:
# export CACHE_READINESS_LOOKBACK_DAYS="2"
# export CACHE_READINESS_MAX_DEGRADATIONS="0"
# export CACHE_READINESS_PREMIUM_FILTER="all" # all|free|premium
# export CACHE_READINESS_REASON_FILTER="all" # all|shared_content_cache_unavailable|generated_shared_content_cache_persist_failed|generated_shared_content_cache_temporarily_unavailable

bash ./scripts/set-generate-horoscope-auth-mode.sh enforce
```

Then run an authenticated rehearsal against a provisioned staging user to prove casing-safe identity matching and deterministic extras stability:

```bash
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_ANON_KEY="<supabase-anon-key>"
export EXPECT_AUTH_MODE="audit" # or enforce during final rehearsal

# Auth source option A (static token pair):
# export AUTH_TEST_BEARER_TOKEN="<jwt-for-provisioned-user>"
# export AUTH_TEST_USER_ID="<same-user-uuid>"

# Auth source option B (recommended; script fetches fresh JWT + user id):
# export AUTH_TEST_USER_EMAIL="<provisioned-user-email>"
# export AUTH_TEST_USER_PASSWORD="<same-user-password>"

# Optional:
# export TARGET_DATE="$(date -u +%F)"
# export CATEGORY="Career"

bash ./scripts/rehearse-auth-rollout.sh
```

Recommended mode switch command (runs readiness guard automatically for `enforce`):

```bash
# Safe promote to enforce (defaults: auth LOOKBACK_DAYS=3/MAX_FALLBACKS=0, cache LOOKBACK_DAYS=2/MAX_DEGRADATIONS=0)
bash ./scripts/set-generate-horoscope-auth-mode.sh enforce

# Roll back or hold in audit if needed
bash ./scripts/set-generate-horoscope-auth-mode.sh audit
bash ./scripts/set-generate-horoscope-auth-mode.sh legacy
```

Emergency override (not recommended): set `SKIP_READINESS_CHECK=true` only when enforce must be applied immediately.

### iOS App Auth Mode Pinning

`OnboardingView` reads `GENERATE_HOROSCOPE_AUTH_MODE` from the app Info.plist.

The `Aura` target now pins this key through build settings:

- `GENERATE_HOROSCOPE_AUTH_MODE` (default: `audit`)
- `INFOPLIST_KEY_GENERATE_HOROSCOPE_AUTH_MODE = $(GENERATE_HOROSCOPE_AUTH_MODE)`

For TestFlight workflows, set the dispatch input `generate_horoscope_auth_mode` (`legacy|audit|enforce`) so archive behavior is explicit per release.
Both workflows now automatically:

- Run `scripts/check-auth-fallback-readiness.sh` and `scripts/check-cache-degradation-readiness.sh` before building when `generate_horoscope_auth_mode=enforce`.
- Use enforce-only dispatch inputs for auth readiness (`enforce_readiness_lookback_days`, `enforce_readiness_max_fallbacks`, `enforce_readiness_auth_context_filter`) and cache readiness (`enforce_cache_readiness_lookback_days`, `enforce_cache_readiness_max_degradations`, `enforce_cache_readiness_premium_filter`, `enforce_cache_readiness_reason_filter`).
- Fail fast if required Supabase readiness secrets are missing for `enforce`.
- Verify the archived app `Info.plist` contains `GENERATE_HOROSCOPE_AUTH_MODE` matching the requested dispatch mode.

### TestFlight Signing Secret Contract

Configure these repository secrets for TestFlight workflows (`testflight.yml` and `testflight-selfhosted.yml`):

- `APPLE_CERTIFICATE_BASE64` (hosted workflow certificate install)
- `APPLE_CERTIFICATE_PASSWORD` (hosted workflow certificate import password)
- `BUILD_PROVISION_PROFILE_BASE64`
- `APPLE_ISSUER_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_PRIVATE_KEY` (raw `.p8` key content)

Legacy key names `APPLE_KEY_ID` / `APPLE_KEY_CONTENT` are no longer used by deploy workflows.

## Production URLs

After deployment, your functions will be available at:

```
https://<project-ref>.supabase.co/functions/v1/referral-redeem
https://<project-ref>.supabase.co/functions/v1/track-share
https://<project-ref>.supabase.co/functions/v1/generate-horoscope
https://<project-ref>.supabase.co/functions/v1/validate-receipt
https://<project-ref>.supabase.co/functions/v1/sync-subscription
```

## Database Migrations

Before deploying functions, ensure database migrations are applied:

```bash
# Apply migrations
supabase db push
```

Migration files are located at:
- `supabase/migrations/20260208_referral_and_share_system.sql`
- `supabase/migrations/20260304_daily_readings_guardrails.sql`
- `supabase/migrations/20260304_generated_reading_cache.sql`
- `supabase/migrations/20260304_generate_horoscope_auth_fallback_audit.sql`
- `supabase/migrations/20260305_generate_horoscope_cache_degradation_audit.sql`
- `supabase/migrations/20260304_popular_warmup_combos.sql`
- `supabase/migrations/20260304_popular_warmup_combos_by_tier.sql`

## Cache Warmup (Recommended)

Warmup pre-generates shared content rows before peak traffic so users avoid first-request latency and OpenAI calls are amortized.

```bash
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_ANON_KEY="<supabase-anon-key>"
export CACHE_WARM_SECRET="<same-secret-set-in-edge-functions>"

# Optional tuning:
# export TARGET_DATE="2026-03-05"
# export WARMUP_LIMIT="20"
# export INCLUDE_PREMIUM="true"
# export WARMUP_CATEGORIES="Career,Love,Social,Health,Personal Growth"
# export WARMUP_LOOKBACK_DAYS="30" # used by dynamic combo builder
# export WARMUP_COMBOS_FILE="./ops/warmup-combos.txt"
# export WARMUP_REQUEST_RETRIES="1"
# export WARMUP_RETRY_DELAY_SECONDS="1"
# export WARMUP_MAX_RETRY_RATE_PERCENT="25" # fail with exit 2 if exceeded
# export WARMUP_METRICS_FILE="./warm-generated-cache.metrics.json" # optional JSON output for run metrics
# export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" # optional for dynamic combos

bash ./scripts/warm-generated-cache.sh
```

The warmup runner reads combinations from `./ops/warmup-combos.txt` by default (or `WARMUP_COMBOS_FILE` override), so ops can tune warm coverage without changing shell logic.
When dynamic combo building is enabled, `INCLUDE_PREMIUM=true` interleaves free-tier and premium-tier demand lists before warming.
Set `WARMUP_METRICS_FILE` to persist machine-readable totals, retry rate, and outcome/exit code for calibration tracking.

### Warmup Threshold Calibration From Metrics

After collecting multiple `warm-generated-cache-metrics` artifacts, summarize them to calibrate `WARMUP_MAX_RETRY_RATE_PERCENT` from observed behavior instead of a fixed guess:

```bash
# Optional knobs:
# export RETRY_RATE_BUFFER_PERCENT="5"             # recommendation = p95 + buffer
# export MIN_RECOMMENDED_RETRY_RATE_PERCENT="20"  # floor for conservative defaults
# export WARMUP_METRICS_SUMMARY_FILE="./ops/warm-cache-metrics-summary.json"

bash ./scripts/summarize-warm-cache-metrics.sh ./ops/warm-cache-metrics
```

The summary prints p50/p95/max retry rates, outcome counts, and a recommended threshold. Keep rollout in audit mode until at least 10 runs are included in the sample.

Apply the recommendation to `.github/workflows/warm-generated-cache.yml` defaults with a confidence guard:

```bash
# Applies recommendation when sample size >=10 (default guard)
bash ./scripts/apply-warmup-threshold-from-metrics.sh ./ops/warm-cache-metrics

# Optional:
# export WARMUP_THRESHOLD_APPLY_DRY_RUN="true"
# export WARMUP_THRESHOLD_MIN_RUNS="12"
# export WARMUP_THRESHOLD_ALLOW_LOW_CONFIDENCE="true" # explicit override
```

### Automated Warmup Threshold Calibration (GitHub Actions)

Workflow file: `.github/workflows/warmup-threshold-calibration.yml`

- Schedule: daily at `01:10 UTC`
- Manual runs: `workflow_dispatch` supports `artifact_limit`, `threshold_min_runs`, `retry_rate_buffer_percent`, `min_recommended_retry_rate_percent`, `allow_low_confidence`, `fail_on_low_confidence`, and `open_pr`
- Behavior:
  1. Downloads recent `warm-generated-cache-metrics` artifacts from Actions history.
  2. Runs `scripts/propose-warmup-threshold-update.sh` (summary + dry-run drift detection + guarded apply).
  3. Uploads calibration logs/JSON artifacts and opens a PR by default when drift is detected.
  4. If no metrics artifacts are available, emits a low-confidence result and skips apply/PR by default (set `fail_on_low_confidence=true` to hard-fail).

Run locally against repository artifacts/history:

```bash
export GH_TOKEN="<github-token-with-actions-read-and-pr-write>"
export GITHUB_REPOSITORY="<owner>/<repo>"
# Optional:
# export WARMUP_THRESHOLD_ARTIFACT_LIMIT="20"
# export WARMUP_THRESHOLD_APPLY_CHANGES="true"
# export WARMUP_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false"

bash ./scripts/propose-warmup-threshold-update.sh
```

### Automated Daily Warmup (GitHub Actions)

Workflow file: `.github/workflows/warm-generated-cache.yml`

- Schedule: daily at `00:05 UTC`
- Manual runs: `workflow_dispatch` supports `target_date`, `warmup_limit`, `include_premium`, `warmup_categories`, `warmup_lookback_days`, `warmup_request_retries`, `warmup_retry_delay_seconds`, and `warmup_max_retry_rate_percent`
- Metrics: uploads `warm-generated-cache-metrics` artifact (`warm-generated-cache.metrics.json`) and appends observed totals/retry-rate/outcome to the step summary.
- Combo source in CI:
  1. Generated from `get_popular_warmup_combos_by_tier` RPC (free + premium interleaving when enabled) when `SUPABASE_SERVICE_ROLE_KEY` is configured.
  2. Falls back to legacy `get_popular_warmup_combos` RPC when tier-aware RPC is unavailable.
  3. Falls back automatically to `./ops/warmup-combos.txt` when dynamic generation is unavailable.

After adding the repository secrets listed in prerequisites, no additional setup is required.

### Automated Auth Fallback Readiness (GitHub Actions)

Workflow file: `.github/workflows/auth-fallback-readiness.yml`

- Schedule: daily at `00:35 UTC`
- Manual runs: `workflow_dispatch` supports `lookback_days`, `max_fallbacks`, `auth_context_filter`, `require_webhook_success`, `escalation_open_issues_max_pages`, and `escalation_closed_issues_max_pages`
- Default gate: `LOOKBACK_DAYS=2` and `MAX_FALLBACKS=0`
- Failure behavior: exits non-zero when fallback volume exceeds threshold (keep auth mode on `audit`)
- Escalation on failure:
  1. Optional webhook POST when `AUTH_FALLBACK_ALERT_WEBHOOK_URL` is configured.
  2. Scan recent open issues first (up to `READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES`, default `10`) and comment on the first matching incident; if none is found, scan closed issues (up to `READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES`, default `10`) and reopen the latest match before creating a new issue.
  3. Set `require_webhook_success=true` on manual runs to fail if webhook delivery is unavailable.
- Recovery behavior: when the gate passes, close the matching open issue (if present) with a recovery comment.

The workflow runs `scripts/check-auth-fallback-readiness.sh`, executes `scripts/run-readiness-escalation.sh` for both failure escalation and recovery closure, uploads `auth-fallback-readiness.log` as an artifact, and writes gate parameters to the GitHub step summary.

### Automated Auth Rollout Rehearsal (GitHub Actions)

Workflow file: `.github/workflows/auth-rollout-rehearsal.yml`

- Trigger: `workflow_dispatch` only (run before mode promotion or enforce-focused release)
- Required secrets: `SUPABASE_PROJECT_REF`, `SUPABASE_ANON_KEY`, and one auth source:
  - Static: `AUTH_TEST_BEARER_TOKEN` + `AUTH_TEST_USER_ID`
  - Dynamic (recommended): `AUTH_TEST_USER_EMAIL` + `AUTH_TEST_USER_PASSWORD`
- Additional required secret when `include_readiness_gates=true`: `SUPABASE_SERVICE_ROLE_KEY`
- Manual inputs:
  - Rehearsal: `expect_auth_mode` (`skip|legacy|audit|enforce`), `category`, `target_date`
  - Optional gate tuning: auth fallback and cache degradation thresholds/filters (same semantics as standalone readiness workflows)
- Behavior:
  1. Optionally runs both readiness gates.
  2. Runs `scripts/rehearse-auth-rollout.sh`.
  3. Uploads logs (`auth-fallback-readiness.log`, `cache-degradation-readiness.log`, `auth-rollout-rehearsal.log`) and appends a step summary.

### Shared Cache Degradation Readiness Check

Use this gate to ensure shared cache degradation volume is stable before stricter rollout or after schema changes:

```bash
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_SERVICE_ROLE_KEY="<supabase-service-role-key>"

# Optional:
# export LOOKBACK_DAYS="2"
# export MAX_DEGRADATIONS="0"
# export PREMIUM_FILTER="all" # all|free|premium
# export REASON_FILTER="all" # all|shared_content_cache_unavailable|generated_shared_content_cache_persist_failed|generated_shared_content_cache_temporarily_unavailable

bash ./scripts/check-cache-degradation-readiness.sh
```

### Automated Shared Cache Degradation Readiness (GitHub Actions)

Workflow file: `.github/workflows/cache-degradation-readiness.yml`

- Schedule: daily at `00:50 UTC`
- Manual runs: `workflow_dispatch` supports `lookback_days`, `max_degradations`, `premium_filter`, `reason_filter`, `require_webhook_success`, `escalation_open_issues_max_pages`, and `escalation_closed_issues_max_pages`
- Default gate: `LOOKBACK_DAYS=2` and `MAX_DEGRADATIONS=0`
- Failure behavior: exits non-zero when degradation volume exceeds threshold
- Escalation on failure:
  1. Optional webhook POST when `CACHE_DEGRADATION_ALERT_WEBHOOK_URL` is configured.
  2. Scan recent open issues first (up to `READINESS_ESCALATION_OPEN_ISSUES_MAX_PAGES`, default `10`) and comment on the first matching incident; if none is found, scan closed issues (up to `READINESS_ESCALATION_CLOSED_ISSUES_MAX_PAGES`, default `10`) and reopen the latest match before creating a new issue.
  3. Set `require_webhook_success=true` on manual runs to fail if webhook delivery is unavailable.
- Recovery behavior: when the gate passes, close the matching open issue (if present) with a recovery comment.

The workflow runs `scripts/check-cache-degradation-readiness.sh`, executes `scripts/run-readiness-escalation.sh` for both failure escalation and recovery closure, uploads `cache-degradation-readiness.log` as an artifact, and writes gate parameters to the GitHub step summary.

### Readiness Escalation Page-Limit Calibration From Metrics

After collecting multiple readiness escalation metrics artifacts, summarize observed issue scan depth before changing workflow defaults:

```bash
# Optional knobs:
# export READINESS_ESCALATION_PAGE_LIMIT_BUFFER_PAGES="1"
# export MIN_RECOMMENDED_OPEN_ISSUES_MAX_PAGES="1"
# export MIN_RECOMMENDED_CLOSED_ISSUES_MAX_PAGES="1"
# export READINESS_ESCALATION_METRICS_SUMMARY_FILE="./ops/readiness-page-limit-summary.json"

bash ./scripts/summarize-readiness-escalation-metrics.sh ./ops/readiness-escalation-metrics
```

The summary prints open/closed scan-depth percentiles, limit-hit rates, and recommended page limits. Keep calibration in audit mode until at least 10 runs are included.

Apply the recommendation to both readiness workflows with a confidence guard:

```bash
# Applies recommendation when sample size >=10 (default guard)
bash ./scripts/apply-readiness-page-limits-from-metrics.sh ./ops/readiness-escalation-metrics

# Optional:
# export READINESS_THRESHOLD_APPLY_DRY_RUN="true"
# export READINESS_THRESHOLD_MIN_RUNS="12"
# export READINESS_THRESHOLD_ALLOW_LOW_CONFIDENCE="true" # explicit override
```

### Automated Readiness Page-Limit Calibration (GitHub Actions)

Workflow file: `.github/workflows/readiness-page-limit-calibration.yml`

- Schedule: daily at `01:25 UTC`
- Manual runs: `workflow_dispatch` supports `artifact_limit`, `threshold_min_runs`, `page_limit_buffer_pages`, `min_recommended_open_issues_max_pages`, `min_recommended_closed_issues_max_pages`, `allow_low_confidence`, `fail_on_low_confidence`, and `open_pr`
- Behavior:
  1. Downloads recent readiness escalation metrics artifacts from both readiness workflows.
  2. Runs `scripts/propose-readiness-page-limit-update.sh` (summary + dry-run drift detection + guarded apply).
  3. Uploads calibration logs/JSON artifacts and opens a PR by default when drift is detected.
  4. If no metrics artifacts are available, emits a low-confidence result and skips apply/PR by default (set `fail_on_low_confidence=true` to hard-fail).

Run locally against repository artifacts/history:

```bash
export GH_TOKEN="<github-token-with-actions-read-and-pr-write>"
export GITHUB_REPOSITORY="<owner>/<repo>"
# Optional:
# export READINESS_PAGE_LIMIT_ARTIFACT_LIMIT="20"
# export READINESS_PAGE_LIMIT_APPLY_CHANGES="true"
# export READINESS_THRESHOLD_FAIL_ON_LOW_CONFIDENCE="false"

bash ./scripts/propose-readiness-page-limit-update.sh
```

## RevenueCat Webhook Configuration

1. Go to RevenueCat Dashboard → Projects → [Your Project] → Webhooks
2. Add new webhook:
   - URL: `https://<project-ref>.supabase.co/functions/v1/sync-subscription`
   - Authorization: `Bearer <REVENUECAT_WEBHOOK_SECRET>`
   - Events: Select all subscription events

## Testing

After deployment, test each function:

### Test Referral Redeem
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/referral-redeem" \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"referral_code": "ABC123"}'
```

### Test Track Share
```bash
# Create share event
curl -X POST "https://<project-ref>.supabase.co/functions/v1/track-share" \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{
    "content_type": "reading",
    "share_platform": "imessage",
    "utm_campaign": "test_campaign"
  }'

# Test click tracking (no auth required)
curl -v "https://<project-ref>.supabase.co/functions/v1/track-share/ABC123XYZ"
```

### Test Validate Receipt
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/validate-receipt" \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"revenuecat_customer_id": "$RCAnonymousID:xxx"}'
```

### Test Generate Horoscope
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/generate-horoscope" \
  -H "Content-Type: application/json" \
  -H "apikey: <supabase-anon-key>" \
  -H "Authorization: Bearer <user-jwt>" \
  -d '{
    "user_id": "00000000-0000-0000-0000-000000000000",
    "zodiac_sign": "Aries",
    "mbti_type": "INTJ",
    "category": "Career",
    "is_premium": false
  }'
```

### Test Warm Cache Endpoint (Generate Horoscope warm mode)
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/generate-horoscope" \
  -H "Content-Type: application/json" \
  -H "apikey: <supabase-anon-key>" \
  -H "x-cache-warm-secret: <CACHE_WARM_SECRET>" \
  -d '{
    "warm_cache": true,
    "zodiac_sign": "Aries",
    "mbti_type": "INTJ",
    "category": "Career",
    "is_premium": false,
    "date": "2026-03-04"
  }'
```

### Test Sync Subscription (Webhook)
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/sync-subscription" \
  -H "Authorization: Bearer <REVENUECAT_WEBHOOK_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "event": {
      "type": "INITIAL_PURCHASE",
      "app_user_id": "user-uuid",
      "product_id": "aura_premium_monthly",
      "entitlement_ids": ["premium"]
    }
  }'
```

## Troubleshooting

### Function deployment fails
- Check Supabase CLI is authenticated: `supabase projects list`
- Verify project reference is correct
- Check function code for syntax errors

### Secrets not set
- Verify you have permission to set secrets
- Check secret names match exactly what functions expect

### Webhook not working
- Verify webhook secret is set correctly
- Check RevenueCat webhook configuration
- Review function logs: `supabase functions logs sync-subscription`

## Security Considerations

1. **Never commit secrets to git**
2. **Use service role key only in edge functions**, never in client code
3. **Store `OPENAI_API_KEY` only as an edge-function secret**
4. **Enable RLS on all tables** (already configured in migrations)
5. **Verify JWT tokens** for authenticated endpoints
6. **Use webhook secrets** to verify webhook authenticity
7. **Use `CACHE_WARM_SECRET`** for warm-cache requests and rotate it periodically
8. **Roll auth mode deliberately**: `audit` first, then `enforce` after client JWT propagation is verified

## Rollback

To rollback a function deployment:

```bash
# Redeploy previous version (if using git)
git checkout <previous-commit>
supabase functions deploy <function-name>
```

Or delete and redeploy:
```bash
# Note: Supabase doesn't have a direct "undeploy" command
# You would need to deploy a "no-op" version or disable the function
```

## Monitoring

Monitor function invocations and errors in the Supabase Dashboard:
- Edge Functions → [Function Name] → Logs
- Database → Logs (for SQL errors)

## Support

For issues or questions:
1. Check Supabase documentation: https://supabase.com/docs
2. Review function logs in dashboard
3. Contact the DevOps team (Yuki)
