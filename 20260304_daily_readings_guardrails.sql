-- ============================================================================
-- Aura Daily Readings Guardrails
-- Migration: 20260304_daily_readings_guardrails
-- Adds backend enforcement for content size and generation-rate checks.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.word_count(input_text TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN input_text IS NULL OR btrim(input_text) = '' THEN 0
        ELSE COALESCE(
            array_length(
                regexp_split_to_array(
                    regexp_replace(btrim(input_text), '[[:space:]]+', ' ', 'g'),
                    '[[:space:]]+'
                ),
                1
            ),
            0
        )
    END;
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'daily_readings'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'daily_readings'
              AND column_name = 'content_version'
        ) THEN
            ALTER TABLE public.daily_readings
                ADD COLUMN content_version INTEGER NOT NULL DEFAULT 1;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'daily_readings'
              AND column_name = 'view_count'
        ) THEN
            ALTER TABLE public.daily_readings
                ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'daily_readings'
              AND column_name = 'shared'
        ) THEN
            ALTER TABLE public.daily_readings
                ADD COLUMN shared BOOLEAN NOT NULL DEFAULT FALSE;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'daily_readings_content_word_limit_chk'
              AND conrelid = 'public.daily_readings'::regclass
        ) THEN
            ALTER TABLE public.daily_readings
                ADD CONSTRAINT daily_readings_content_word_limit_chk
                CHECK (
                    public.word_count(content) > 0
                    AND public.word_count(content) <= CASE
                        WHEN is_premium THEN 350
                        ELSE 150
                    END
                ) NOT VALID;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'daily_readings_content_char_limit_chk'
              AND conrelid = 'public.daily_readings'::regclass
        ) THEN
            ALTER TABLE public.daily_readings
                ADD CONSTRAINT daily_readings_content_char_limit_chk
                CHECK (char_length(content) <= 5000)
                NOT VALID;
        END IF;
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'daily_readings'
    ) THEN
        EXECUTE $fn$
        CREATE OR REPLACE FUNCTION public.check_rate_limit(
            p_user_id UUID,
            p_category TEXT,
            p_date DATE DEFAULT CURRENT_DATE
        )
        RETURNS TABLE (
            allowed BOOLEAN,
            existing_reading_id UUID,
            reason TEXT
        )
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = public
        AS $function$
        DECLARE
            v_existing_id UUID;
        BEGIN
            SELECT id
            INTO v_existing_id
            FROM public.daily_readings
            WHERE user_id = p_user_id
              AND category = p_category
              AND date = p_date
            LIMIT 1;

            IF v_existing_id IS NULL THEN
                RETURN QUERY SELECT true, NULL::UUID, 'ok'::TEXT;
            ELSE
                RETURN QUERY SELECT false, v_existing_id, 'already_generated_for_day'::TEXT;
            END IF;
        END;
        $function$;
        $fn$;

        REVOKE ALL ON FUNCTION public.check_rate_limit(UUID, TEXT, DATE) FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION public.check_rate_limit(UUID, TEXT, DATE) TO authenticated;
        GRANT EXECUTE ON FUNCTION public.check_rate_limit(UUID, TEXT, DATE) TO service_role;
    END IF;
END $$;
