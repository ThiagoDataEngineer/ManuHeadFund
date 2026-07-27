-- SETUP_SUPABASE_MENTOR_SHADOW_OBSERVATIONS_2026_07_27.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Contexto (2026-07-27): Invoke-MentorShadowObservation (lib_mentor_shadow.ps1)
-- roda a cascade Triagem->Mesa->Mentor (LLM real) em modo observacao desde
-- 2026-07-24, mas so grava em journal/mentor_shadow_log.jsonl -- arquivo local
-- do runner efemero do GitHub Actions, descartado ao fim de cada job. Owner
-- quer usar a nota de conviccao do Mentor como parte do "score de nascimento"
-- de cada trade, mas isso exige validar primeiro se essa nota correlaciona
-- com resultado real -- impossivel sem historico persistente. Mesmo padrao
-- ja corrigido para beta_history/conviction_observations no mesmo mes.
--
-- mentor_confidence (0-100) e o dado novo que o log local NUNCA gravava --
-- so decisao binaria (APROVAR/SKIP) + motivo. Precisamos do numero pra
-- cruzar com trade_outcomes.pnl_percent depois de acumular volume.
--
-- pk_id formato "MARKET_DIRECTION_TIMESTAMP" (mesmo padrao de
-- conviction_observations) permite upsert idempotente.

CREATE TABLE IF NOT EXISTS manuheadfund.mentor_shadow_observations (
    pk_id             TEXT PRIMARY KEY,
    ts_utc            TEXT NOT NULL,
    market            TEXT NOT NULL,
    real_direction    TEXT,
    real_usd_size     NUMERIC,
    llm_decision      TEXT,           -- APROVAR | SKIP | UNKNOWN
    mentor_confidence NUMERIC,        -- 0-100, nota real do Mentor LLM (nunca persistida antes)
    llm_motivo        TEXT,
    triagem_tier      TEXT,
    mesa_consensus    TEXT,
    agrees_with_real  BOOLEAN,        -- llm_decision == APROVAR (o real ja executou sempre)
    elapsed_ms        INTEGER,
    created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mentor_shadow_market ON manuheadfund.mentor_shadow_observations(market);
CREATE INDEX IF NOT EXISTS idx_mentor_shadow_ts ON manuheadfund.mentor_shadow_observations(ts_utc DESC);

ALTER TABLE manuheadfund.mentor_shadow_observations ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.mentor_shadow_observations TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "mentor_shadow_observations_all" ON manuheadfund.mentor_shadow_observations;
CREATE POLICY "mentor_shadow_observations_all" ON manuheadfund.mentor_shadow_observations
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
