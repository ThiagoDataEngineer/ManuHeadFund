-- SETUP_SUPABASE_GEM_POSITION_EVENTS_2026_07_29.sql
-- Achado real (2026-07-29): DOGEUSDT SHORT recebeu 12 "Add Positions" reais
-- em ~17h (965 DOGE cada, somando exatamente o open_interest final de 11597)
-- porque o guard "CASCADING ADD POSITION PREVENTION" (gem_executor.ps1,
-- 2026-07-07) lia de journal/trade_outcomes.jsonl -- arquivo LOCAL que
-- nunca sobrevive no runner efemero do GitHub Actions -- e comparava
-- contra campos (.market/.entry_date/status="open") que nunca existiram
-- no schema real de trade_outcomes. O limite de "maximo 3 Add Positions/6h"
-- nunca bloqueou nada de verdade.
--
-- Tabela nova e dedicada: registra CADA execucao real de ordem GEM
-- (abertura OU reforco), persistida no Supabase (sobrevive entre runs).

CREATE TABLE IF NOT EXISTS manuheadfund.gem_position_events (
    id         TEXT PRIMARY KEY,
    market     TEXT NOT NULL,
    side       TEXT NOT NULL,
    usd_size   NUMERIC,
    event_type TEXT NOT NULL,  -- 'OPEN' | 'ADD'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gem_position_events_market_type
    ON manuheadfund.gem_position_events (market, event_type, created_at DESC);

NOTIFY pgrst, 'reload schema';
