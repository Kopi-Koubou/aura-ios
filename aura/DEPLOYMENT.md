# Aura Backend Deployment Guide

## Overview

This document describes how to deploy the Aura monetization backend to Supabase production.

## Edge Functions

The following edge functions need to be deployed:

| Function | Purpose | Auth Required |
|----------|---------|---------------|
| `referral-redeem` | Referral code redemption with rate limiting | Yes |
| `track-share` | Share tracking with UTM parameters | No (GET), Yes (POST) |
| `validate-receipt` | RevenueCat receipt validation | Yes |
| `sync-subscription` | Subscription webhook handler | No (webhook secret) |

## Prerequisites

1. Supabase CLI installed (`brew install supabase`)
2. Access to 1Password Kato vault
3. Supabase project created (production)
4. RevenueCat account with API keys
5. PostHog account (optional, for analytics)

## Quick Deploy

### Step 1: Authenticate with Supabase

```bash
supabase login
```

### Step 2: Set Environment Variables

```bash
export SUPABASE_PROJECT_REF="your-project-ref"  # e.g., "aura-prod-xxxxx"
```

### Step 3: Deploy Functions

```bash
cd /Users/devl/clawd/projects/horoscope-app/aura
./scripts/deploy-functions.sh
```

### Step 4: Set Secrets

```bash
./scripts/set-secrets.sh
```

## Manual Deployment

If you prefer to deploy manually:

### Deploy Individual Functions

```bash
# Link to project
supabase link --project-ref $SUPABASE_PROJECT_REF

# Deploy each function
supabase functions deploy referral-redeem
supabase functions deploy track-share
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
```

## Production URLs

After deployment, your functions will be available at:

```
https://<project-ref>.supabase.co/functions/v1/referral-redeem
https://<project-ref>.supabase.co/functions/v1/track-share
https://<project-ref>.supabase.co/functions/v1/validate-receipt
https://<project-ref>.supabase.co/functions/v1/sync-subscription
```

## Database Migrations

Before deploying functions, ensure database migrations are applied:

```bash
# Apply migrations
supabase db push
```

The migration file is located at:
`supabase/migrations/20260208_referral_and_share_system.sql`

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
3. **Enable RLS on all tables** (already configured in migrations)
4. **Verify JWT tokens** for authenticated endpoints
5. **Use webhook secrets** to verify webhook authenticity

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
