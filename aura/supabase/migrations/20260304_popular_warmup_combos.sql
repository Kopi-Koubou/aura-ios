-- ============================================================================
-- Aura Warmup Combo Analytics
-- Migration: 20260304_popular_warmup_combos
-- Adds RPC to derive high-demand zodiac/MBTI pairs for cache warmup.
-- ============================================================================

DO $$
BEGIN
    EXECUTE $fn$
    CREATE OR REPLACE FUNCTION public.get_popular_warmup_combos(
        p_limit INTEGER DEFAULT 20,
        p_lookback_days INTEGER DEFAULT 30
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
    END;
    $function$;
    $fn$;

    REVOKE ALL ON FUNCTION public.get_popular_warmup_combos(INTEGER, INTEGER) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.get_popular_warmup_combos(INTEGER, INTEGER) TO service_role;
END $$;
