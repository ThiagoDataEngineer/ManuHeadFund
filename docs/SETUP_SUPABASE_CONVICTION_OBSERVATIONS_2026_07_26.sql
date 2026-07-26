-- SETUP_SUPABASE_CONVICTION_OBSERVATIONS_2026_07_26.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Fix: warning "table 'conviction_observations' ausente no Supabase
-- (PGRST205)" em toda execucao de scripts/cloud_conviction_scan.ps1.
--
-- Contexto do achado (2026-07-26): cloud_conviction_scan.ps1 roda desde
-- 2026-06-18 (>5 semanas) com objetivo EXPLICITO documentado no proprio
-- cabecalho do script -- "acumular ~1 semana de observacoes p/ validar
-- edge ANTES de virar execucao" (decidir se o Threshold=75 hardcoded em
-- Resolve-ConvictionOverride, gate que destrava tori_skip, deveria mudar
-- com base em dado real). Mas a tabela nunca foi criada -- toda execucao
-- falhava silenciosamente (try/catch engolindo o erro), caindo no fallback
-- local (journal/conviction_observations.jsonl), que por sua vez roda no
-- runner efemero do GitHub Actions e e descartado ao fim de cada job.
-- Resultado: ZERO dado real se acumulou em 5+ semanas -- nao era so "falta
-- fazer a analise depois", a fonte de dado nunca existiu de fato. Mesmo
-- padrao ja corrigido para beta_history e fqs_registry no mesmo dia.
--
-- pk_id como PRIMARY KEY (formato "MARKET_DIRECTION_TIMESTAMP", ja gerado
-- pelo proprio script): permite upsert idempotente, nunca cresce com
-- duplicatas do mesmo scan.

CREATE TABLE IF NOT EXISTS manuheadfund.conviction_observations (
    pk_id       TEXT PRIMARY KEY,
    ts          TEXT NOT NULL,          -- "yyyy-MM-dd HH:mm:ss" (formato do script, sem TZ)
    market      TEXT NOT NULL,
    direction   TEXT NOT NULL,          -- LONG | SHORT
    conviction  NUMERIC NOT NULL,       -- 0-100, media ponderada do ensemble de eixos
    ready       BOOLEAN,
    tag         TEXT,                   -- OVERRIDE (>=75) | READY (55-74) | below (<55)
    chg_24h     NUMERIC,
    axes        TEXT,                   -- JSON compact dos eixos individuais (axes_detail)
    mode        TEXT DEFAULT 'OBSERVE',
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conviction_observations_market ON manuheadfund.conviction_observations(market);
CREATE INDEX IF NOT EXISTS idx_conviction_observations_tag ON manuheadfund.conviction_observations(tag);
CREATE INDEX IF NOT EXISTS idx_conviction_observations_ts ON manuheadfund.conviction_observations(ts DESC);

ALTER TABLE manuheadfund.conviction_observations ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.conviction_observations TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "conviction_observations_all" ON manuheadfund.conviction_observations;
CREATE POLICY "conviction_observations_all" ON manuheadfund.conviction_observations
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
