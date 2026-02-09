#!/bin/bash
# Quick Start Deployment Script for Aura Backend
# Run this after creating the Supabase project

set -e

echo "=========================================="
echo "Aura Backend - Quick Deployment"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running from correct directory
if [ ! -d "edge-functions" ] || [ ! -f "config.toml" ]; then
    echo -e "${RED}Error: Must run from /Users/devl/clawd/Aura directory${NC}"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Step 1: Get project reference
echo -e "${BLUE}Step 1: Supabase Project Configuration${NC}"
echo ""

if [ -z "$SUPABASE_PROJECT_REF" ]; then
    echo -e "${YELLOW}SUPABASE_PROJECT_REF not set.${NC}"
    echo "Please enter your Supabase project reference (found in Project Settings > API):"
    read -p "Project Ref: " SUPABASE_PROJECT_REF
    export SUPABASE_PROJECT_REF
fi

echo -e "Project Ref: ${GREEN}$SUPABASE_PROJECT_REF${NC}"
echo ""

# Step 2: Check 1Password access
echo -e "${BLUE}Step 2: Loading credentials from 1Password...${NC}"

if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    if [ -f "/Users/devl/clawd/.env" ]; then
        source /Users/devl/clawd/.env
        export OP_SERVICE_ACCOUNT_TOKEN
    fi
fi

if [ -z "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo -e "${YELLOW}Warning: OP_SERVICE_ACCOUNT_TOKEN not set.${NC}"
    echo "You'll need to manually enter credentials."
    MANUAL_CREDENTIALS=true
else
    echo -e "${GREEN}✓ 1Password service account configured${NC}"
    MANUAL_CREDENTIALS=false
fi
echo ""

# Step 3: Link to project
echo -e "${BLUE}Step 3: Linking to Supabase project...${NC}"
if supabase link --project-ref "$SUPABASE_PROJECT_REF"; then
    echo -e "${GREEN}✓ Project linked successfully${NC}"
else
    echo -e "${RED}✗ Failed to link project${NC}"
    echo "Please ensure you have access to the project and the project ref is correct."
    exit 1
fi
echo ""

# Step 4: Apply database migrations
echo -e "${BLUE}Step 4: Applying database migrations...${NC}"
if [ -f "20260208_referral_and_share_system.sql" ]; then
    echo "Found migration file. Applying..."
    if supabase db push; then
        echo -e "${GREEN}✓ Migrations applied${NC}"
    else
        echo -e "${YELLOW}⚠ Migration push failed or already applied${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No migration file found${NC}"
fi
echo ""

# Step 5: Deploy functions
echo -e "${BLUE}Step 5: Deploying edge functions...${NC}"
FUNCTIONS=("referral-redeem" "track-share" "validate-receipt" "sync-subscription")

for func in "${FUNCTIONS[@]}"; do
    echo -n "Deploying $func... "
    if supabase functions deploy "$func" --project-ref "$SUPABASE_PROJECT_REF" 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done
echo ""

# Step 6: Set secrets
echo -e "${BLUE}Step 6: Setting edge function secrets...${NC}"

if [ "$MANUAL_CREDENTIALS" = true ]; then
    echo "Please enter the following secrets:"
    read -p "SUPABASE_URL: " SUPABASE_URL
    read -p "SUPABASE_SERVICE_ROLE_KEY: " SUPABASE_SERVICE_ROLE_KEY
    read -p "REVENUECAT_API_KEY: " REVENUECAT_API_KEY
    read -p "REVENUECAT_WEBHOOK_SECRET: " REVENUECAT_WEBHOOK_SECRET
    read -p "POSTHOG_API_KEY (optional): " POSTHOG_API_KEY
else
    echo "Fetching from 1Password..."
    SUPABASE_URL=$(op item get "Aura - Supabase" --vault="Kato" --fields "Project URL" --reveal 2>/dev/null || echo "")
    SUPABASE_SERVICE_ROLE_KEY=$(op item get "Aura - Supabase" --vault="Kato" --fields "Service Key" --reveal 2>/dev/null || echo "")
    REVENUECAT_API_KEY=$(op item get "RevenueCat - Aura" --vault="Kato" --fields "API Key" --reveal 2>/dev/null || echo "")
    REVENUECAT_WEBHOOK_SECRET=$(op item get "RevenueCat - Aura" --vault="Kato" --fields "Webhook Secret" --reveal 2>/dev/null || echo "")
    POSTHOG_API_KEY=$(op item get "PostHog - Aura" --vault="Kato" --fields "API Key" --reveal 2>/dev/null || echo "")
fi

echo "Setting secrets..."
[ -n "$SUPABASE_URL" ] && supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "SUPABASE_URL=$SUPABASE_URL" && echo -e "${GREEN}✓ SUPABASE_URL${NC}"
[ -n "$SUPABASE_SERVICE_ROLE_KEY" ] && supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY" && echo -e "${GREEN}✓ SUPABASE_SERVICE_ROLE_KEY${NC}"
[ -n "$REVENUECAT_API_KEY" ] && supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "REVENUECAT_API_KEY=$REVENUECAT_API_KEY" && echo -e "${GREEN}✓ REVENUECAT_API_KEY${NC}"
[ -n "$REVENUECAT_WEBHOOK_SECRET" ] && supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "REVENUECAT_WEBHOOK_SECRET=$REVENUECAT_WEBHOOK_SECRET" && echo -e "${GREEN}✓ REVENUECAT_WEBHOOK_SECRET${NC}"
[ -n "$POSTHOG_API_KEY" ] && supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "POSTHOG_API_KEY=$POSTHOG_API_KEY" && echo -e "${GREEN}✓ POSTHOG_API_KEY${NC}"
echo ""

# Step 7: Verify deployment
echo -e "${BLUE}Step 7: Verifying deployment...${NC}"
BASE_URL="https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1"

echo "Testing endpoints..."
echo ""
echo "Referral Redeem: $BASE_URL/referral-redeem"
echo "Track Share:     $BASE_URL/track-share"
echo "Validate Receipt: $BASE_URL/validate-receipt"
echo "Sync Subscription: $BASE_URL/sync-subscription"
echo ""

# Final summary
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Configure RevenueCat webhook:"
echo "     URL: $BASE_URL/sync-subscription"
echo ""
echo "  2. Update iOS app with production URLs:"
echo "     SUPABASE_URL: $SUPABASE_URL"
echo ""
echo "  3. Test the endpoints (see DEPLOYMENT.md for examples)"
echo ""
echo "  4. Monitor functions in Supabase Dashboard:"
echo "     https://supabase.com/dashboard/project/$SUPABASE_PROJECT_REF/functions"
echo ""
