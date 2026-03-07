-- ============================================================================
-- Aura Generate Horoscope Auth Fallback Audit
-- Migration: 20260304_generate_horoscope_auth_fallback_audit
-- Persists fallback usage in audit mode to support enforce-readiness checks.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.generate_horoscope_auth_fallback_daily (
    date DATE NOT NULL,
    category TEXT NOT NULL,
    auth_context TEXT NOT NULL,
    fallback_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT generate_horoscope_auth_fallback_daily_pk PRIMARY KEY (date, category, auth_context),
    CONSTRAINT generate_horoscope_auth_fallback_daily_category_chk CHECK (
        category IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth')
    ),
    CONSTRAINT generate_horoscope_auth_fallback_daily_auth_context_chk CHECK (
        auth_context IN ('missing', 'invalid')
    ),
    CONSTRAINT generate_horoscope_auth_fallback_daily_count_chk CHECK (fallback_count >= 0)
);

ALTER TABLE public.generate_horoscope_auth_fallback_daily ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'generate_horoscope_auth_fallback_daily'
          AND policyname = 'Service role manage generate horoscope auth fallback audit'
    ) THEN
        CREATE POLICY "Service role manage generate horoscope auth fallback audit"
            ON public.generate_horoscope_auth_fallback_daily
            FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

REVOKE ALL ON TABLE public.generate_horoscope_auth_fallback_daily FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON TABLE public.generate_horoscope_auth_fallback_daily TO service_role;

CREATE OR REPLACE FUNCTION public.record_generate_horoscope_auth_fallback(
    p_date DATE,
    p_category TEXT,
    p_auth_context TEXT
)
RETURNS TABLE (fallback_count INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_category TEXT;
    v_auth_context TEXT;
BEGIN
    IF p_date IS NULL THEN
        RAISE EXCEPTION 'p_date is required';
    END IF;

    v_category := btrim(COALESCE(p_category, ''));
    v_auth_context := lower(btrim(COALESCE(p_auth_context, '')));

    IF v_category = '' THEN
        RAISE EXCEPTION 'p_category is required';
    END IF;

    IF v_auth_context = '' THEN
        RAISE EXCEPTION 'p_auth_context is required';
    END IF;

    IF v_category NOT IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth') THEN
        RAISE EXCEPTION 'p_category is invalid: %', v_category;
    END IF;

    IF v_auth_context NOT IN ('missing', 'invalid') THEN
        RAISE EXCEPTION 'p_auth_context is invalid: %', v_auth_context;
    END IF;

    RETURN QUERY
    INSERT INTO public.generate_horoscope_auth_fallback_daily (
        date,
        category,
        auth_context,
        fallback_count,
        created_at,
        updated_at
    )
    VALUES (
        p_date,
        v_category,
        v_auth_context,
        1,
        NOW(),
        NOW()
    )
    ON CONFLICT (date, category, auth_context)
    DO UPDATE
       SET fallback_count = public.generate_horoscope_auth_fallback_daily.fallback_count + 1,
           updated_at = NOW()
    RETURNING public.generate_horoscope_auth_fallback_daily.fallback_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_generate_horoscope_auth_fallback(DATE, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_generate_horoscope_auth_fallback(DATE, TEXT, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.get_generate_horoscope_auth_fallback_summary(
    p_start_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    date DATE,
    category TEXT,
    auth_context TEXT,
    fallback_count INTEGER,
    updated_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        audit.date,
        audit.category,
        audit.auth_context,
        audit.fallback_count,
        audit.updated_at
    FROM public.generate_horoscope_auth_fallback_daily AS audit
    WHERE audit.date >= COALESCE(p_start_date, CURRENT_DATE)
    ORDER BY audit.date DESC, audit.category ASC, audit.auth_context ASC;
$$;

REVOKE ALL ON FUNCTION public.get_generate_horoscope_auth_fallback_summary(DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_generate_horoscope_auth_fallback_summary(DATE) TO service_role;
