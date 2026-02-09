#!/bin/bash
# Aura Edge Functions Deployment Script
# This script deploys all edge functions to Supabase production

set -e

echo "=========================================="
echo "Aura Edge Functions Deployment"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "supabase/config.toml" ]; then
    echo -e "${RED}Error: Must run from project root directory${NC}"
    exit 1
fi

# Function to deploy edge functions
deploy_function() {
    local func_name=$1
    echo -e "${YELLOW}Deploying $func_name...${NC}"
    
    if supabase functions deploy "$func_name" --project-ref "$SUPABASE_PROJECT_REF"; then
        echo -e "${GREEN}✓ $func_name deployed successfully${NC}"
    else
        echo -e "${RED}✗ Failed to deploy $func_name${NC}"
        return 1
    fi
}

# Check environment variables
if [ -z "$SUPABASE_PROJECT_REF" ]; then
    echo -e "${RED}Error: SUPABASE_PROJECT_REF not set${NC}"
    echo "Please set the Supabase project reference (e.g., aura-prod)"
    exit 1
fi

echo ""
echo "Project Reference: $SUPABASE_PROJECT_REF"
echo ""

# Deploy each function
deploy_function "referral-redeem"
deploy_function "track-share"
deploy_function "validate-receipt"
deploy_function "sync-subscription"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}All functions deployed successfully!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Function URLs:"
echo "  • referral-redeem:  https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/referral-redeem"
echo "  • track-share:      https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/track-share"
echo "  • validate-receipt: https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/validate-receipt"
echo "  • sync-subscription: https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/sync-subscription"
echo ""
echo "Next steps:"
echo "  1. Set required secrets using: ./scripts/set-secrets.sh"
echo "  2. Test functions using: ./scripts/test-functions.sh"
echo "  3. Configure RevenueCat webhook to point to sync-subscription URL"
