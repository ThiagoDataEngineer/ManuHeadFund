-- ALTER_TRAILING_UNIFIED_SHADOW_ADD_COLUMNS_2026_07_30.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- trailing_stop_monitor.ps1 (commit bc89952, promocao do motor unificado a
-- ativo) passou a gravar 2 colunas novas em manuheadfund.trailing_unified_shadow
-- que nao existiam na tabela original (SETUP_SUPABASE_TRAILING_UNIFIED_SHADOW_2026_07_19.sql):
--   - trendline_factor (fator multiplicativo da trendline Tori, 0.4-1.0)
--   - pushed_live (se o stop realmente foi empurrado pra CoinEx nesse ciclo)
-- Confirmado em producao (run 30512459814, 2026-07-30): erro repetido
-- "Could not find the 'pushed_live' column of 'trailing_unified_shadow' in
-- the schema cache" a cada posicao avaliada -- o insert falha silenciosamente
-- (fail-soft catch), entao a tabela de telemetria fica sem dados novos desde
-- a promocao, apesar do motor real estar funcionando corretamente.

ALTER TABLE manuheadfund.trailing_unified_shadow
    ADD COLUMN IF NOT EXISTS trendline_factor NUMERIC,
    ADD COLUMN IF NOT EXISTS pushed_live BOOLEAN;

NOTIFY pgrst, 'reload schema';

-- VERIFY:
-- SELECT market, side, real_stop, unified_action, unified_new_stop, trendline_factor,
--        pushed_live, reason, ts
--   FROM manuheadfund.trailing_unified_shadow ORDER BY ts DESC LIMIT 20;
