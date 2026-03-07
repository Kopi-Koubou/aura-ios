-- ============================================================================
-- Aura Generated Reading Cache
-- Migration: 20260304_generated_reading_cache
-- Adds shared cache rows keyed by date + zodiac + MBTI + category + tier.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.generated_reading_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    date DATE NOT NULL,
    zodiac_sign TEXT NOT NULL,
    mbti_type TEXT NOT NULL,
    category TEXT NOT NULL,
    is_premium BOOLEAN NOT NULL DEFAULT FALSE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT generated_reading_cache_zodiac_chk CHECK (
        zodiac_sign IN (
            'Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo',
            'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'
        )
    ),
    CONSTRAINT generated_reading_cache_mbti_chk CHECK (
        mbti_type IN (
            'INTJ', 'INTP', 'ENTJ', 'ENTP',
            'INFJ', 'INFP', 'ENFJ', 'ENFP',
            'ISTJ', 'ISFJ', 'ESTJ', 'ESFJ',
            'ISTP', 'ISFP', 'ESTP', 'ESFP'
        )
    ),
    CONSTRAINT generated_reading_cache_category_chk CHECK (
        category IN ('Career', 'Love', 'Social', 'Health', 'Personal Growth')
    ),
    CONSTRAINT generated_reading_cache_content_not_empty_chk CHECK (char_length(btrim(content)) > 0),
    CONSTRAINT generated_reading_cache_content_char_limit_chk CHECK (char_length(content) <= 5000)
);

CREATE UNIQUE INDEX IF NOT EXISTS generated_reading_cache_combo_unique_idx
    ON public.generated_reading_cache (date, zodiac_sign, mbti_type, category, is_premium);

CREATE INDEX IF NOT EXISTS generated_reading_cache_date_idx
    ON public.generated_reading_cache (date DESC);

ALTER TABLE public.generated_reading_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'generated_reading_cache'
          AND policyname = 'Service role manage generated reading cache'
    ) THEN
        CREATE POLICY "Service role manage generated reading cache"
            ON public.generated_reading_cache
            FOR ALL
            TO service_role
            USING (true)
            WITH CHECK (true);
    END IF;
END $$;

REVOKE ALL ON TABLE public.generated_reading_cache FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.generated_reading_cache TO service_role;
