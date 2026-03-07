-- ============================================================================
-- Aura Warmup Combo Analytics
-- Migration: 20260304_popular_warmup_combos_by_tier
-- Adds tier-aware RPC to derive high-demand zodiac/MBTI pairs for cache warmup.
-- ============================================================================

DO $$
BEGIN
    EXECUTE $fn$
    CREATE OR REPLACE FUNCTION public.get_popular_warmup_combos_by_tier(
        p_limit INTEGER DEFAULT 20,
        p_lookback_days INTEGER DEFAULT 30,
        p_is_premium BOOLEAN DEFAULT false
    )
    RETURNS TABLE (
        zodiac_sign TEXT,
        mbti_type TEXT,
        demand_score BIGINT
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $function$
    DECLARE
        v_limit INTEGER := GREATEST(1, LEAST(COALESCE(p_limit, 20), 200));
        v_lookback_days INTEGER := GREATEST(1, LEAST(COALESCE(p_lookback_days, 30), 365));
        v_is_premium BOOLEAN := COALESCE(p_is_premium, false);
        v_has_is_premium BOOLEAN := false;
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name = 'users'
        ) OR NOT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name = 'daily_readings'
        ) THEN
            RETURN;
        END IF;

        SELECT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'daily_readings'
              AND column_name = 'is_premium'
        )
        INTO v_has_is_premium;

        IF NOT v_has_is_premium THEN
            RETURN QUERY
            WITH recent_demand AS (
                SELECT
                    u.zodiac_sign,
                    u.mbti_type,
                    COUNT(*)::BIGINT AS demand_score
                FROM public.daily_readings d
                JOIN public.users u ON u.id = d.user_id
                WHERE d.date >= (CURRENT_DATE - (v_lookback_days - 1))
                GROUP BY u.zodiac_sign, u.mbti_type
            ),
            user_distribution AS (
                SELECT
                    u.zodiac_sign,
                    u.mbti_type,
                    COUNT(*)::BIGINT AS demand_score
                FROM public.users u
                GROUP BY u.zodiac_sign, u.mbti_type
            ),
            selected AS (
                SELECT * FROM recent_demand
                UNION ALL
                SELECT * FROM user_distribution
                WHERE NOT EXISTS (SELECT 1 FROM recent_demand)
            )
            SELECT
                selected.zodiac_sign,
                selected.mbti_type,
                selected.demand_score
            FROM selected
            WHERE selected.zodiac_sign IS NOT NULL
              AND selected.mbti_type IS NOT NULL
            ORDER BY selected.demand_score DESC, selected.zodiac_sign ASC, selected.mbti_type ASC
            LIMIT v_limit;

            RETURN;
        END IF;

        RETURN QUERY
        WITH recent_demand_tier AS (
            SELECT
                u.zodiac_sign,
                u.mbti_type,
                COUNT(*)::BIGINT AS demand_score
            FROM public.daily_readings d
            JOIN public.users u ON u.id = d.user_id
            WHERE d.date >= (CURRENT_DATE - (v_lookback_days - 1))
              AND COALESCE(d.is_premium, false) = v_is_premium
            GROUP BY u.zodiac_sign, u.mbti_type
        ),
        recent_demand_all AS (
            SELECT
                u.zodiac_sign,
                u.mbti_type,
                COUNT(*)::BIGINT AS demand_score
            FROM public.daily_readings d
            JOIN public.users u ON u.id = d.user_id
            WHERE d.date >= (CURRENT_DATE - (v_lookback_days - 1))
            GROUP BY u.zodiac_sign, u.mbti_type
        ),
        user_distribution AS (
            SELECT
                u.zodiac_sign,
                u.mbti_type,
                COUNT(*)::BIGINT AS demand_score
            FROM public.users u
            GROUP BY u.zodiac_sign, u.mbti_type
        ),
        selected AS (
            SELECT * FROM recent_demand_tier
            UNION ALL
            SELECT * FROM recent_demand_all
            WHERE NOT EXISTS (SELECT 1 FROM recent_demand_tier)
              AND EXISTS (SELECT 1 FROM recent_demand_all)
            UNION ALL
            SELECT * FROM user_distribution
            WHERE NOT EXISTS (SELECT 1 FROM recent_demand_tier)
              AND NOT EXISTS (SELECT 1 FROM recent_demand_all)
        )
        SELECT
            selected.zodiac_sign,
            selected.mbti_type,
            selected.demand_score
        FROM selected
        WHERE selected.zodiac_sign IS NOT NULL
          AND selected.mbti_type IS NOT NULL
        ORDER BY selected.demand_score DESC, selected.zodiac_sign ASC, selected.mbti_type ASC
        LIMIT v_limit;
    END;
    $function$;
    $fn$;

    REVOKE ALL ON FUNCTION public.get_popular_warmup_combos_by_tier(INTEGER, INTEGER, BOOLEAN) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.get_popular_warmup_combos_by_tier(INTEGER, INTEGER, BOOLEAN) TO service_role;
END $$;
