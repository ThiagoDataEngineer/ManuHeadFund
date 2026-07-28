-- SETUP_SUPABASE_DECISION_REFLECTIONS_2026_07_28.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Contexto (2026-07-28): lib_decision_reflection.ps1 (E3, 2026-05-22) ja
-- implementa o ciclo completo "decisao -> outcome -> licao LLM-destilada":
--   1. Add-PendingReflection grava decisao original (veredito/confianca/
--      mensagem do Mentor + sinal da Mesa + tier) quando o trade abre
--      (chamada real: lib_trailing.ps1 Add-TrailingPosition/Close-TrailingPosition).
--   2. cron_mentor_reflector.ps1 (job real "Layer 2 - Mentor 6h Reflection",
--      roda a cada 30min em producao) cruza com o outcome real, calcula
--      alpha vs BTC, gera reflexao via Haiku (2-4 frases) e grava resolved.
--   3. Build-MentorFullContext injeta as ultimas 5 reflections RESOLVED da
--      MESMA moeda no prompt do Mentor antes da proxima decisao -- literal
--      "memoria por moeda" pro LLM consultar antes de agir sozinho.
--
-- Mas tudo isso le/escreve em journal/decision_reflections.jsonl -- arquivo
-- LOCAL no runner efemero do GitHub Actions (checkout limpo a cada job).
-- Get-PriorReflectionsForMarket SEMPRE retorna vazio em producao real --
-- o Mentor decide toda vez sem NENHUM historico da moeda, apesar do
-- mecanismo inteiro (geracao da licao via LLM incluida) ja estar pronto e
-- conectado. Mesmo padrao ja corrigido hoje para beta_history/
-- conviction_observations/mentor_shadow_observations.
--
-- Design: 1 linha por trade_id, upsert conforme o ciclo avanca (pending ->
-- resolved) -- reflete exatamente como Get-PriorReflectionsForMarket ja
-- junta os dois estados hoje (by trade_id, so retorna quando resolved
-- preenchido). status permite filtrar so os "pending" abertos (cron
-- reflector) ou "resolved" (consulta do Mentor).

CREATE TABLE IF NOT EXISTS manuheadfund.decision_reflections (
    trade_id          TEXT PRIMARY KEY,
    market            TEXT NOT NULL,
    entry_date_utc     TEXT,
    mentor_veredicto  TEXT,           -- EXECUTAR | REVISAR | ABORTAR (na abertura)
    mentor_confidence NUMERIC,        -- 0-100 (na abertura)
    mentor_mensagem   TEXT,           -- texto original do Mentor (na abertura)
    mesa_sinal        TEXT,           -- LONG | SHORT | NEUTRO
    tier              TEXT,           -- A_LIVE | A_PAPER | B_PAPER | GEM
    status            TEXT NOT NULL DEFAULT 'pending',  -- pending | resolved
    exit_date_utc     TEXT,
    pnl_pct           NUMERIC,
    alpha_vs_btc      NUMERIC,
    holding_days      INTEGER,
    reflection        TEXT,           -- licao destilada por LLM (2-4 frases), so quando resolved
    added_at          TIMESTAMPTZ,
    resolved_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_decision_reflections_market ON manuheadfund.decision_reflections(market);
CREATE INDEX IF NOT EXISTS idx_decision_reflections_status ON manuheadfund.decision_reflections(status);
CREATE INDEX IF NOT EXISTS idx_decision_reflections_resolved_at ON manuheadfund.decision_reflections(resolved_at DESC);

ALTER TABLE manuheadfund.decision_reflections ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.decision_reflections TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "decision_reflections_all" ON manuheadfund.decision_reflections;
CREATE POLICY "decision_reflections_all" ON manuheadfund.decision_reflections
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
