-- FIX 2026-07-14: colunas ausentes causando PGRST204 em todo ciclo de trailing.
--
-- Achado durante investigacao "por que QUAI/SXT/SENT aparecem como PHANTOM em
-- TODO ciclo, nao so uma vez": Close-TrailingPosition (lib_trailing.ps1:251-253)
-- grava closedAt/closeReason/exitPrice em manuheadfund.trailing_state -- essas
-- colunas nunca existiram no SQL de setup (SETUP_SUPABASE_MANUHEADFUND_2026_07_09.
-- sql). A escrita falha silenciosamente (best-effort), cai para arquivo local do
-- runner efemero do GitHub Actions, que e destruido ao fim do job -- o proximo
-- ciclo faz checkout limpo, le o Supabase de novo (ainda active=true), phantom
-- e "fechado" outra vez. Loop infinito de falso-fechamento, nunca persiste de
-- verdade.
--
-- RODADA 1 (2026-07-14 18:xx) so cobriu closeReason -- corrigida via ALTER,
-- confirmada via RAISE EXCEPTION real, mas PGRST204 continuou. Restart manual
-- do PostgREST via Supabase Dashboard confirmou a hipotese: a proxima falha
-- (rota real Save-StateRecords, nao o teste isolado) revelou 'closedAt' TAMBEM
-- ausente -- eu so tinha corrigido o campo mencionado no primeiro erro, sem
-- auditar a funcao inteira. Corrigido agora: closedAt, closeReason, exitPrice.
--
-- Mesmo padrao em manuheadfund.trade_outcomes: ConvertTo-SupabaseOutcome
-- (lib_feedback_loop.ps1:126-139) mapeia pra um shape (market/side/mode/entry/
-- stop/target/r_multiple/closed_at/close_reason/payload) COMPLETAMENTE
-- diferente do schema real (symbol/direction/entry_price/quantity/pnl_realized/
-- pnl_percent/status/regime/has_confluence/conviction_score) -- tabela de uma
-- geracao anterior do sistema, nunca migrada pro shape atual. So exit_price e
-- source batem. Adicionadas todas as colunas que faltam (nullable, nao quebra
-- linhas existentes).
--
-- ADD COLUMN IF NOT EXISTS e idempotente e nao-destrutivo -- seguro rodar
-- mesmo se alguma coluna ja existir.

ALTER TABLE manuheadfund.trailing_state
    ADD COLUMN IF NOT EXISTS "closeReason" TEXT,
    ADD COLUMN IF NOT EXISTS "closedAt" TEXT,
    ADD COLUMN IF NOT EXISTS "exitPrice" NUMERIC;

ALTER TABLE manuheadfund.trade_outcomes
    ADD COLUMN IF NOT EXISTS close_reason TEXT,
    ADD COLUMN IF NOT EXISTS market TEXT,
    ADD COLUMN IF NOT EXISTS side TEXT,
    ADD COLUMN IF NOT EXISTS mode TEXT,
    ADD COLUMN IF NOT EXISTS entry FLOAT8,
    ADD COLUMN IF NOT EXISTS stop FLOAT8,
    ADD COLUMN IF NOT EXISTS target FLOAT8,
    ADD COLUMN IF NOT EXISTS r_multiple FLOAT8,
    ADD COLUMN IF NOT EXISTS closed_at TEXT,
    ADD COLUMN IF NOT EXISTS payload JSONB;

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

NOTIFY pgrst, 'reload schema';

-- Verificacao pos-migração (rodar manualmente para confirmar, ou usar
-- scripts/diag_check_close_reason_2026_07_14.ps1 -- exec_sql SEMPRE retorna
-- 'ok', nao confiar em verificacao via SELECT simples atraves dele):
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema='manuheadfund' AND table_name='trailing_state'
--   AND column_name IN ('closeReason','closedAt','exitPrice');
-- SELECT column_name FROM information_schema.columns
--   WHERE table_schema='manuheadfund' AND table_name='trade_outcomes'
--   AND column_name IN ('close_reason','market','side','mode','entry','stop','target','r_multiple','closed_at','payload');
-- SELECT table_name FROM information_schema.tables
--   WHERE table_schema='manuheadfund' AND table_name='spot_stop_failures';
