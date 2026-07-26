-- SETUP_SUPABASE_BETA_HISTORY_2026_07_26.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Fix: warning "table 'beta_history' missing (PGRST205, cached)" em todo
-- ciclo real (Publish-BetaToSupabase, lib_beta_calculator_multitf.ps1).
--
-- Contexto do achado (2026-07-26): mentor_agent.ps1 le esta tabela desde
-- 2026-07-07 esperando o beta (correlacao altcoin vs BTC) de cada mercado
-- pra montar o contexto do Mentor LLM -- mas a funcao que deveria escrever
-- aqui (Sync-AllBetasMultiTF) chamava "Get-CoinexCandles" com assinatura
-- errada (funcao que nunca existiu em lib_coinex.ps1), entao NUNCA
-- publicou nada, em nenhum ambiente, desde a criacao. "beta ausente"
-- aparecia em quase todo veto do Mentor como consequencia direta. O bug de
-- codigo ja foi corrigido (commit 2a38e5f); esta tabela e o passo final
-- pra persistir o dado calculado entre ciclos.
--
-- market como PRIMARY KEY (nao id serial): Publish-BetaToSupabase agora
-- faz upsert via -PrimaryKey "market" -- 1 linha por mercado, sempre a
-- mais recente (evita crescimento ilimitado + leitura de linha historica
-- desatualizada por Get-StateRecords sem ORDER BY explicito).

CREATE TABLE IF NOT EXISTS manuheadfund.beta_history (
    market      TEXT PRIMARY KEY,
    beta        NUMERIC NOT NULL,       -- beta_weighted (1D=50%, 4H=30%, 1H=20%), usado pelo Mentor
    beta_1d     NUMERIC,
    beta_4h     NUMERIC,
    beta_1h     NUMERIC,
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_beta_history_timestamp ON manuheadfund.beta_history("timestamp" DESC);

ALTER TABLE manuheadfund.beta_history ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.beta_history TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "beta_history_all" ON manuheadfund.beta_history;
CREATE POLICY "beta_history_all" ON manuheadfund.beta_history
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
