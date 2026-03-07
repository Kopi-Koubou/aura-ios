-- ============================================================================
-- Aura Generate Horoscope Shared Cache Degradation Audit
-- Migration: 20260305_generate_horoscope_cache_degradation_audit
-- Persists cache degradation counters for readiness checks and alerting.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.generate_horoscope_shared_cache_degradation_daily (
    date DATE NOT NULL,
    category TEXT NOT NULL,
    is_premium BOOLEAN NOT NULL DEFAULT false,
    resolution_reason TEXT NOT NULL,
    degradation_count INTEGER NOT NULL DEFAULT 0,
    lookup_failed_count INTEGER NOT NULL DEFAULT 0,
    persist_failed_count INTEGER NOT NULL DEFAULT 0,
    temporarily_unavailable_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_pk PRIMARY KEY (
        date,
        category,
        is_premium,
        resolution_reason
    ),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_category_chk CHECK (
        category IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth')
    ),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_reason_chk CHECK (
        resolution_reason IN (
            'shared_content_cache_unavailable',
            'generated_shared_content_cache_persist_failed',
            'generated_shared_content_cache_temporarily_unavailable'
        )
    ),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_degradation_count_chk CHECK (degradation_count >= 0),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_lookup_count_chk CHECK (lookup_failed_count >= 0),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_persist_count_chk CHECK (persist_failed_count >= 0),
    CONSTRAINT generate_horoscope_shared_cache_degradation_daily_temporary_count_chk CHECK (temporarily_unavailable_count >= 0)
);

ALTER TABLE public.generate_horoscope_shared_cache_degradation_daily ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'generate_horoscope_shared_cache_degradation_daily'
          AND policyname = 'Service role manage generate horoscope shared cache degradation audit'
    ) THEN
        CREATE POLICY "Service role manage generate horoscope shared cache degradation audit"
            ON public.generate_horoscope_shared_cache_degradation_daily
            FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

REVOKE ALL ON TABLE public.generate_horoscope_shared_cache_degradation_daily FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON TABLE public.generate_horoscope_shared_cache_degradation_daily TO service_role;

CREATE OR REPLACE FUNCTION public.record_generate_horoscope_shared_cache_degradation(
    p_date DATE,
    p_category TEXT,
    p_is_premium BOOLEAN,
    p_resolution_reason TEXT,
    p_lookup_failed BOOLEAN DEFAULT false,
    p_persist_failed BOOLEAN DEFAULT false,
    p_temporarily_unavailable BOOLEAN DEFAULT false
)
RETURNS TABLE (
    degradation_count INTEGER,
    temporarily_unavailable_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_category TEXT;
    v_is_premium BOOLEAN;
    v_resolution_reason TEXT;
    v_lookup_failed BOOLEAN;
    v_persist_failed BOOLEAN;
    v_temporarily_unavailable BOOLEAN;
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'p_date is required';
    END IF;

    v_category := btrim(COALESCE(p_category, ''));
    v_resolution_reason := lower(btrim(COALESCE(p_resolution_reason, '')));
    v_is_premium := COALESCE(p_is_premium, false);
    v_lookup_failed := COALESCE(p_lookup_failed, false);
    v_persist_failed := COALESCE(p_persist_failed, false);
    v_temporarily_unavailable := COALESCE(p_temporarily_unavailable, false);

    IF v_category = '' THEN
        RAISE EXCEPTION 'p_category is required';
    END IF;

    IF v_resolution_reason = '' THEN
        RAISE EXCEPTION 'p_resolution_reason is required';
    END IF;

    IF v_category NOT IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth') THEN
        RAISE EXCEPTION 'p_category is invalid: %', v_category;
    END IF;

    IF v_resolution_reason NOT IN (
        'shared_content_cache_unavailable',
        'generated_shared_content_cache_persist_failed',
        'generated_shared_content_cache_temporarily_unavailable'
    ) THEN
        RAISE EXCEPTION 'p_resolution_reason is invalid: %', v_resolution_reason;
    END IF;

    RETURN QUERY
    INSERT INTO public.generate_horoscope_shared_cache_degradation_daily (
        date,
        category,
        is_premium,
        resolution_reason,
        degradation_count,
        lookup_failed_count,
        persist_failed_count,
        temporarily_unavailable_count,
        created_at,
        updated_at
    )
    VALUES (
        p_date,
        v_category,
        v_is_premium,
        v_resolution_reason,
        1,
        CASE WHEN v_lookup_failed THEN 1 ELSE 0 END,
        CASE WHEN v_persist_failed THEN 1 ELSE 0 END,
        CASE WHEN v_temporarily_unavailable THEN 1 ELSE 0 END,
        NOW(),
        NOW()
    )
    ON CONFLICT (date, category, is_premium, resolution_reason)
    DO UPDATE
       SET degradation_count = public.generate_horoscope_shared_cache_degradation_daily.degradation_count + 1,
           lookup_failed_count =
               public.generate_horoscope_shared_cache_degradation_daily.lookup_failed_count
               + CASE WHEN v_lookup_failed THEN 1 ELSE 0 END,
           persist_failed_count =
               public.generate_horoscope_shared_cache_degradation_daily.persist_failed_count
               + CASE WHEN v_persist_failed THEN 1 ELSE 0 END,
           temporarily_unavailable_count =
               public.generate_horoscope_shared_cache_degradation_daily.temporarily_unavailable_count
               + CASE WHEN v_temporarily_unavailable THEN 1 ELSE 0 END,
           updated_at = NOW()
    RETURNING
        public.generate_horoscope_shared_cache_degradation_daily.degradation_count,
        public.generate_horoscope_shared_cache_degradation_daily.temporarily_unavailable_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_generate_horoscope_shared_cache_degradation(
    DATE,
    TEXT,
    BOOLEAN,
    TEXT,
    BOOLEAN,
    BOOLEAN,
    BOOLEAN
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_generate_horoscope_shared_cache_degradation(
    DATE,
    TEXT,
    BOOLEAN,
    TEXT,
    BOOLEAN,
    BOOLEAN,
    BOOLEAN
) TO service_role;

CREATE OR REPLACE FUNCTION public.get_generate_horoscope_shared_cache_degradation_summary(
    p_start_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    date DATE,
    category TEXT,
    is_premium BOOLEAN,
    resolution_reason TEXT,
    degradation_count INTEGER,
    lookup_failed_count INTEGER,
    persist_failed_count INTEGER,
    temporarily_unavailable_count INTEGER,
    updated_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        audit.date,
        audit.category,
        audit.is_premium,
        audit.resolution_reason,
        audit.degradation_count,
        audit.lookup_failed_count,
        audit.persist_failed_count,
        audit.temporarily_unavailable_count,
        audit.updated_at
    FROM public.generate_horoscope_shared_cache_degradation_daily AS audit
    WHERE audit.date >= COALESCE(p_start_date, CURRENT_DATE)
    ORDER BY audit.date DESC, audit.category ASC, audit.is_premium ASC, audit.resolution_reason ASC;
$$;

REVOKE ALL ON FUNCTION public.get_generate_horoscope_shared_cache_degradation_summary(DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_generate_horoscope_shared_cache_degradation_summary(DATE) TO service_role;
