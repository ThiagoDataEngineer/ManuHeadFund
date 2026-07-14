-- FIX 2026-07-14: colunas ausentes causando PGRST204 em todo ciclo de trailing.
--
-- Achado durante investigacao "por que QUAI/SXT/SENT aparecem como PHANTOM em
-- TODO ciclo, nao so uma vez": Close-TrailingPosition (lib_trailing.ps1:252)
-- grava closeReason em manuheadfund.trailing_state -- coluna nunca existiu no
-- SQL de setup (SETUP_SUPABASE_MANUHEADFUND_2026_07_09.sql). A escrita falha
-- silenciosamente (best-effort), cai para arquivo local do runner efemero do
-- GitHub Actions, que e destruido ao fim do job -- o proximo ciclo faz checkout
-- limpo, le o Supabase de novo (ainda active=true), phantom e "fechado" outra
-- vez. Loop infinito de falso-fechamento, nunca persiste de verdade.
--
-- Mesmo padrao em manuheadfund.trade_outcomes: ConvertTo-SupabaseOutcome
-- (lib_feedback_loop.ps1:136) grava close_reason, coluna tambem ausente.
--
-- ADD COLUMN IF NOT EXISTS e idempotente e nao-destrutivo -- seguro rodar
-- mesmo se alguma coluna ja existir.

ALTER TABLE manuheadfund.trailing_state
    ADD COLUMN IF NOT EXISTS "closeReason" TEXT;

ALTER TABLE manuheadfund.trade_outcomes
    ADD COLUMN IF NOT EXISTS close_reason TEXT;

-- spot_stop_failures: circuit breaker de falhas consecutivas de stop SPOT
-- (position_watcher.ps1). Precisa viver no Supabase -- arquivo local em
-- journal/*.jsonl nao sobrevive entre runs do GitHub Actions (runner efemero,
-- checkout limpo a cada job). Mesmo problema estrutural do trailing_state acima,
-- descoberto ao revisar o fix desta sessao contra a cadencia real da nuvem.
CREATE TABLE IF NOT EXISTS manuheadfund.spot_stop_failures (
    pk_id   TEXT PRIMARY KEY,
    market  TEXT NOT NULL,
    action  TEXT,
    detail  TEXT,
    ts      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_spot_stop_failures_market_ts ON manuheadfund.spot_stop_failures (market, ts DESC);
GRANT ALL ON manuheadfund.spot_stop_failures TO anon, authenticated, service_role;

-- Verificacao pos-migração (rodar manualmente para confirmar):
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema='manuheadfund' AND table_name='trailing_state' AND column_name='closeReason';
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema='manuheadfund' AND table_name='trade_outcomes' AND column_name='close_reason';
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema='manuheadfund' AND table_name='spot_stop_failures';
