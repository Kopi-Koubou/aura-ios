-- ============================================================================
-- Aura Referral and Share System
-- Migration: 20260208_referral_and_share_system
-- ============================================================================

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- REFERRAL CODES TABLE
-- Stores unique referral codes for each user
-- ============================================================================

CREATE TABLE IF NOT EXISTS referral_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    code VARCHAR(10) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    times_used INTEGER DEFAULT 0,
    max_uses INTEGER DEFAULT NULL, -- NULL = unlimited
    expires_at TIMESTAMPTZ DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookups
CREATE INDEX idx_referral_codes_code ON referral_codes(code) WHERE is_active = true;
CREATE INDEX idx_referral_codes_user_id ON referral_codes(user_id);

-- ============================================================================
-- REFERRAL REDEMPTIONS TABLE
-- Tracks when users redeem referral codes
-- ============================================================================

CREATE TABLE IF NOT EXISTS referral_redemptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referral_code_id UUID NOT NULL REFERENCES referral_codes(id) ON DELETE CASCADE,
    referrer_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    redeemed_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    reward_days INTEGER NOT NULL DEFAULT 7,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Each user can only redeem one referral code ever
    CONSTRAINT unique_redeemed_by_user UNIQUE (redeemed_by_user_id)
);

-- Index for analytics queries
CREATE INDEX idx_referral_redemptions_referrer ON referral_redemptions(referrer_user_id);
CREATE INDEX idx_referral_redemptions_created_at ON referral_redemptions(created_at);

-- ============================================================================
-- SHARE EVENTS TABLE
-- Tracks all share events with platform and content type
-- ============================================================================

CREATE TYPE share_platform AS ENUM (
    'imessage',
    'instagram',
    'instagram_story',
    'twitter',
    'facebook',
    'whatsapp',
    'telegram',
    'snapchat',
    'tiktok',
    'email',
    'copy_link',
    'other'
);

CREATE TYPE share_content_type AS ENUM (
    'reading',
    'mbti_result',
    'weekly_forecast',
    'compatibility',
    'profile'
);

CREATE TABLE IF NOT EXISTS share_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_type share_content_type NOT NULL,
    content_id UUID DEFAULT NULL, -- References reading, result, etc.
    share_platform share_platform NOT NULL,
    deep_link_id VARCHAR(8) NOT NULL UNIQUE,
    utm_campaign VARCHAR(100) DEFAULT NULL,
    referral_code_id UUID REFERENCES referral_codes(id) ON DELETE SET NULL,
    click_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for analytics and lookups
CREATE INDEX idx_share_events_user_id ON share_events(user_id);
CREATE INDEX idx_share_events_deep_link_id ON share_events(deep_link_id);
CREATE INDEX idx_share_events_platform ON share_events(share_platform);
CREATE INDEX idx_share_events_content_type ON share_events(content_type);
CREATE INDEX idx_share_events_created_at ON share_events(created_at);

-- ============================================================================
-- SHARE CLICK EVENTS TABLE
-- Detailed tracking of each click on shared links
-- ============================================================================

CREATE TABLE IF NOT EXISTS share_click_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    share_event_id UUID NOT NULL REFERENCES share_events(id) ON DELETE CASCADE,
    user_agent TEXT DEFAULT NULL,
    referrer TEXT DEFAULT NULL,
    ip_country VARCHAR(2) DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_share_click_events_share_event_id ON share_click_events(share_event_id);
CREATE INDEX idx_share_click_events_created_at ON share_click_events(created_at);

-- ============================================================================
-- ADD REFERRAL FIELDS TO SUBSCRIPTIONS TABLE
-- (Assumes subscriptions table already exists)
-- ============================================================================

DO $$
BEGIN
    -- Add referral-related columns if they don't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'subscriptions' AND column_name = 'is_referral_reward'
    ) THEN
        ALTER TABLE subscriptions ADD COLUMN is_referral_reward BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'subscriptions' AND column_name = 'referral_premium_expires_at'
    ) THEN
        ALTER TABLE subscriptions ADD COLUMN referral_premium_expires_at TIMESTAMPTZ DEFAULT NULL;
    END IF;
END $$;

-- ============================================================================
-- FUNCTION: Increment share click count
-- Called by the track-share edge function
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_share_clicks(link_id TEXT)
RETURNS void AS $$
BEGIN
    UPDATE share_events
    SET click_count = click_count + 1
    WHERE deep_link_id = link_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION: Generate unique referral code for new users
-- Can be called via trigger on user creation
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_referral_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    code TEXT := '';
    i INTEGER;
    exists_check BOOLEAN;
BEGIN
    LOOP
        code := '';
        FOR i IN 1..8 LOOP
            code := code || substr(chars, floor(random() * length(chars) + 1)::int, 1);
        END LOOP;

        -- Check if code already exists
        SELECT EXISTS(SELECT 1 FROM referral_codes WHERE referral_codes.code = generate_referral_code.code) INTO exists_check;

        IF NOT exists_check THEN
            RETURN code;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION: Create referral code for new user
-- ============================================================================

CREATE OR REPLACE FUNCTION create_user_referral_code(p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    new_code TEXT;
    new_id UUID;
BEGIN
    new_code := generate_referral_code();

    INSERT INTO referral_codes (user_id, code)
    VALUES (p_user_id, new_code)
    RETURNING id INTO new_id;

    RETURN new_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- TRIGGER: Auto-create referral code for new users
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_new_user_referral()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM create_user_referral_code(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger (drop first if exists to avoid duplicates)
DROP TRIGGER IF EXISTS on_auth_user_created_referral ON auth.users;

CREATE TRIGGER on_auth_user_created_referral
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_user_referral();

-- ============================================================================
-- ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_click_events ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- REFERRAL CODES POLICIES
-- -----------------------------------------------------------------------------

-- Users can view their own referral code
CREATE POLICY "Users can view own referral codes"
    ON referral_codes FOR SELECT
    USING (auth.uid() = user_id);

-- Anyone can lookup an active referral code by code value (for validation)
CREATE POLICY "Anyone can lookup active referral codes"
    ON referral_codes FOR SELECT
    USING (is_active = true);

-- Only service role can insert/update (via edge functions)
-- No direct user insert/update policies needed

-- -----------------------------------------------------------------------------
-- REFERRAL REDEMPTIONS POLICIES
-- -----------------------------------------------------------------------------

-- Users can view redemptions where they are the referrer or redeemer
CREATE POLICY "Users can view own redemptions"
    ON referral_redemptions FOR SELECT
    USING (
        auth.uid() = referrer_user_id
        OR auth.uid() = redeemed_by_user_id
    );

-- Only service role can insert (via edge function)
-- No direct user insert policies needed

-- -----------------------------------------------------------------------------
-- SHARE EVENTS POLICIES
-- -----------------------------------------------------------------------------

-- Users can view their own share events
CREATE POLICY "Users can view own share events"
    ON share_events FOR SELECT
    USING (auth.uid() = user_id);

-- Users can insert their own share events (or via edge function)
CREATE POLICY "Users can create share events"
    ON share_events FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Public can read share events by deep_link_id (for click tracking)
CREATE POLICY "Public can read share events by deep link"
    ON share_events FOR SELECT
    USING (true); -- Allow public read for redirect tracking

-- -----------------------------------------------------------------------------
-- SHARE CLICK EVENTS POLICIES
-- -----------------------------------------------------------------------------

-- Click events are insert-only (no auth required for tracking)
CREATE POLICY "Anyone can insert click events"
    ON share_click_events FOR INSERT
    WITH CHECK (true);

-- Users can view click events for their own shares
CREATE POLICY "Users can view clicks on own shares"
    ON share_click_events FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM share_events
            WHERE share_events.id = share_click_events.share_event_id
            AND share_events.user_id = auth.uid()
        )
    );

-- ============================================================================
-- ANALYTICS VIEWS
-- ============================================================================

-- View: User referral stats
CREATE OR REPLACE VIEW user_referral_stats AS
SELECT
    rc.user_id,
    rc.code,
    rc.times_used,
    rc.created_at,
    COALESCE(SUM(rr.reward_days), 0) as total_reward_days_earned,
    COUNT(rr.id) as successful_referrals
FROM referral_codes rc
LEFT JOIN referral_redemptions rr ON rr.referrer_user_id = rc.user_id
WHERE rc.is_active = true
GROUP BY rc.id, rc.user_id, rc.code, rc.times_used, rc.created_at;

-- View: Share analytics by platform
CREATE OR REPLACE VIEW share_analytics_by_platform AS
SELECT
    user_id,
    share_platform,
    content_type,
    COUNT(*) as share_count,
    SUM(click_count) as total_clicks,
    ROUND(AVG(click_count)::numeric, 2) as avg_clicks_per_share,
    DATE_TRUNC('day', created_at) as share_date
FROM share_events
GROUP BY user_id, share_platform, content_type, DATE_TRUNC('day', created_at);

-- Grant select on views to authenticated users
GRANT SELECT ON user_referral_stats TO authenticated;
GRANT SELECT ON share_analytics_by_platform TO authenticated;

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE referral_codes IS 'Unique referral codes for each user, auto-generated on signup';
COMMENT ON TABLE referral_redemptions IS 'Records of referral code redemptions with reward tracking';
COMMENT ON TABLE share_events IS 'All share events with platform, content type, and UTM tracking';
COMMENT ON TABLE share_click_events IS 'Detailed click tracking for shared links';

COMMENT ON FUNCTION increment_share_clicks IS 'Increments click count for a share event by deep_link_id';
COMMENT ON FUNCTION generate_referral_code IS 'Generates a unique 8-character referral code';
COMMENT ON FUNCTION create_user_referral_code IS 'Creates a referral code for a user';
