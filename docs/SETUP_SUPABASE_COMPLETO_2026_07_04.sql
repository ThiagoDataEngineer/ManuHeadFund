-- SETUP_SUPABASE_COMPLETO_2026_07_04.sql
-- Auditoria 2026-07-04: 9 de 12 tabelas do state store NUNCA existiram
-- (init_supabase_schema.ps1 dependia do RPC exec_sql que nao existe -> falhava
-- silenciosamente desde sempre). Consequencias em producao: "FQS indisponivel",
-- "beta ABSENT", counterfactual so-local, jobs da nuvem em fallback cego.
--
-- EXECUTAR UMA VEZ no SQL Editor:
--   https://supabase.com/dashboard/project/urcqtpklpfyvizcgcsia/sql/new
-- (cola tudo -> Run. Idempotente: IF NOT EXISTS em tudo.)
--
-- Padroniza schema PUBLIC (default do lib_state_store). Copia dados existentes
-- de manuheadfund.capital_context / trade_outcomes se ainda nao copiados.

-- ── 1. Tabelas de qualidade/risco por ativo ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.fqs_registry (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    fqs_score NUMERIC,
    fqs_category TEXT,
    quality_tier TEXT,
    blue_chip BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fqs_market ON public.fqs_registry(market);

CREATE TABLE IF NOT EXISTS public.beta_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    beta NUMERIC,
    beta_vs_btc NUMERIC,
    beta_category TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_beta_market ON public.beta_history(market);

CREATE TABLE IF NOT EXISTS public.drawdown_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    max_drawdown NUMERIC,
    drawdown_category TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_drawdown_market ON public.drawdown_history(market);

CREATE TABLE IF NOT EXISTS public.dsr_global (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    dsr_score NUMERIC,
    dsr_category TEXT,
    n_trades INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_dsr_market ON public.dsr_global(market);

CREATE TABLE IF NOT EXISTS public.alpha_history (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL,
    alpha_score NUMERIC,
    "timestamp" TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(market, "timestamp")
);
CREATE INDEX IF NOT EXISTS idx_alpha_market ON public.alpha_history(market);

-- ── 2. Estado de mercado ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.regime_state (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    regime TEXT,
    phase TEXT,
    bias TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_regime_market ON public.regime_state(market);

CREATE TABLE IF NOT EXISTS public.tori_proximity (
    id BIGSERIAL PRIMARY KEY,
    market TEXT NOT NULL UNIQUE,
    support_level NUMERIC,
    resistance_level NUMERIC,
    proximity_score NUMERIC,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tori_market ON public.tori_proximity(market);

-- ── 3. Learning / counterfactual ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.trade_rejections (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL,
    market TEXT NOT NULL,
    direction TEXT NOT NULL,
    gate TEXT NOT NULL,
    entry_price NUMERIC NOT NULL,
    exit_price NUMERIC,
    regime TEXT,
    source TEXT DEFAULT 'regime',
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trade_rejections_ts ON public.trade_rejections(ts DESC);
CREATE INDEX IF NOT EXISTS idx_trade_rejections_market ON public.trade_rejections(market);

CREATE TABLE IF NOT EXISTS public.conviction_observations (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ DEFAULT NOW(),
    market TEXT,
    direction TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_conv_obs_market ON public.conviction_observations(market);

-- ── 4. Tabelas que existiam SO em manuheadfund: cria em public + copia dados ─
CREATE TABLE IF NOT EXISTS public.capital_context AS
    SELECT * FROM manuheadfund.capital_context WITH NO DATA;
INSERT INTO public.capital_context
    SELECT * FROM manuheadfund.capital_context m
    WHERE NOT EXISTS (SELECT 1 FROM public.capital_context LIMIT 1);

CREATE TABLE IF NOT EXISTS public.trade_outcomes AS
    SELECT * FROM manuheadfund.trade_outcomes WITH NO DATA;
INSERT INTO public.trade_outcomes
    SELECT * FROM manuheadfund.trade_outcomes m
    WHERE NOT EXISTS (SELECT 1 FROM public.trade_outcomes LIMIT 1);

-- ── 5. RPC exec_sql (para o init/migracoes automatizadas funcionarem) ────────
-- SECURITY: so service_role executa (REVOKE de todos os outros).
CREATE OR REPLACE FUNCTION public.exec_sql(sql TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    EXECUTE sql;
    RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.exec_sql(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.exec_sql(TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.exec_sql(TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.exec_sql(TEXT) TO service_role;

-- ── 6. Verificacao final (deve listar 12+ tabelas) ───────────────────────────
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('fqs_registry','beta_history','drawdown_history','dsr_global',
    'alpha_history','regime_state','tori_proximity','trade_rejections',
    'conviction_observations','capital_context','trade_outcomes','trailing_positions')
ORDER BY table_name;
