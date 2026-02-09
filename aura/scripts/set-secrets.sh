#!/bin/bash
# Set Supabase Edge Function Secrets
# This script sets all required secrets for the Aura edge functions

set -e

echo "=========================================="
echo "Setting Aura Edge Function Secrets"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check project ref
if [ -z "$SUPABASE_PROJECT_REF" ]; then
    echo -e "${RED}Error: SUPABASE_PROJECT_REF not set${NC}"
    exit 1
fi

# Function to set secret
set_secret() {
    local name=$1
    local value=$2
    
    if [ -z "$value" ]; then
        echo -e "${YELLOW}Warning: $name is empty, skipping...${NC}"
        return 0
    fi
    
    echo "Setting $name..."
    if supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "$name=$value"; then
        echo -e "${GREEN}✓ $name set${NC}"
    else
        echo -e "${RED}✗ Failed to set $name${NC}"
        return 1
    fi
}

# Load secrets from environment or 1Password
echo ""
echo "Loading secrets..."

# If running in CI/automation, secrets should be in env vars
# Otherwise, fetch from 1Password
if [ -z "$SUPABASE_URL" ]; then
    echo "Fetching secrets from 1Password..."
    source /Users/devl/clawd/.env
    export OP_SERVICE_ACCOUNT_TOKEN
    
    # Get Aura Supabase credentials
    SUPABASE_URL=$(op item get "Aura - Supabase" --vault="Kato" --fields "Project URL" --reveal 2>/dev/null || echo "")
    SUPABASE_SERVICE_ROLE_KEY=$(op item get "Aura - Supabase" --vault="Kato" --fields "Service Key" --reveal 2>/dev/null || echo "")
    REVENUECAT_API_KEY=$(op item get "RevenueCat - Aura" --vault="Kato" --fields "API Key" --reveal 2>/dev/null || echo "")
    REVENUECAT_WEBHOOK_SECRET=$(op item get "RevenueCat - Aura" --vault="Kato" --fields "Webhook Secret" --reveal 2>/dev/null || echo "")
    POSTHOG_API_KEY=$(op item get "PostHog - Aura" --vault="Kato" --fields "API Key" --reveal 2>/dev/null || echo "")
fi

# Set secrets
echo ""
echo "Setting edge function secrets..."
set_secret "SUPABASE_URL" "$SUPABASE_URL"
set_secret "SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_ROLE_KEY"
set_secret "REVENUECAT_API_KEY" "$REVENUECAT_API_KEY"
set_secret "REVENUECAT_WEBHOOK_SECRET" "$REVENUECAT_WEBHOOK_SECRET"
set_secret "POSTHOG_API_KEY" "$POSTHOG_API_KEY"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}All secrets set successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Secrets configured:"
echo "  • SUPABASE_URL"
echo "  • SUPABASE_SERVICE_ROLE_KEY"
echo "  • REVENUECAT_API_KEY"
echo "  • REVENUECAT_WEBHOOK_SECRET"
echo "  • POSTHOG_API_KEY"
