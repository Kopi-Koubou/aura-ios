-- ============================================================================
-- Aura Generated Reading Cache Retention
-- Migration: 20260305_generated_reading_cache_retention
-- Adds RPC to purge stale generated cache rows and bound long-term storage growth.
-- ============================================================================

DO $$
BEGIN
    EXECUTE $fn$
    CREATE OR REPLACE FUNCTION public.purge_generated_reading_cache(
        p_retention_days INTEGER DEFAULT 3
    )
    RETURNS TABLE (
        deleted_count BIGINT,
        retention_days INTEGER,
        cutoff_date DATE,
        remaining_count BIGINT
    )
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $function$
    DECLARE
        v_retention_days INTEGER := GREATEST(1, LEAST(COALESCE(p_retention_days, 3), 30));
        v_cutoff_date DATE := CURRENT_DATE - (v_retention_days - 1);
        v_deleted_count BIGINT := 0;
        v_remaining_count BIGINT := 0;
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name = 'generated_reading_cache'
        ) THEN
            RETURN QUERY SELECT 0::BIGINT, v_retention_days, v_cutoff_date, 0::BIGINT;
            RETURN;
        END IF;

        WITH deleted AS (
            DELETE FROM public.generated_reading_cache
            WHERE date < v_cutoff_date
            RETURNING 1
        )
        SELECT COUNT(*)::BIGINT
        INTO v_deleted_count
        FROM deleted;

        SELECT COUNT(*)::BIGINT
        INTO v_remaining_count
        FROM public.generated_reading_cache;

        RETURN QUERY
        SELECT v_deleted_count, v_retention_days, v_cutoff_date, v_remaining_count;
    END;
    $function$;
    $fn$;

    REVOKE ALL ON FUNCTION public.purge_generated_reading_cache(INTEGER) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.purge_generated_reading_cache(INTEGER) TO service_role;
END $$;
