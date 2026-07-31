-- SETUP_SUPABASE_PARTIAL_EXIT_LADDERS_2026_07_31.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Register-PartialExitLadder (agents/lib_trailing_partial_exit.ps1) registra
-- um ladder de saida parcial REAL na corretora (CoinEx-PlaceMultiExitLadder)
-- quando o motor de trailing unificado recomenda PARTIAL/EXIT. Precisa de
-- idempotencia real (nao registrar de novo a cada ciclo de 5min) -- essa
-- tabela persiste "ja registrei o ladder pra essa posicao" no Supabase
-- (sobrevive entre runs do GitHub Actions, mesma classe de fix ja aplicada
-- em gem_position_events/llm_usage/trailing_state).

CREATE TABLE IF NOT EXISTS manuheadfund.partial_exit_ladders (
    id            BIGSERIAL PRIMARY KEY,
    market        TEXT NOT NULL,
    active        BOOLEAN NOT NULL DEFAULT true,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    levels_json   TEXT,
    created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partial_exit_ladders_market ON manuheadfund.partial_exit_ladders(market);
CREATE INDEX IF NOT EXISTS idx_partial_exit_ladders_active ON manuheadfund.partial_exit_ladders(market, active);

GRANT SELECT, INSERT ON manuheadfund.partial_exit_ladders TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE manuheadfund.partial_exit_ladders_id_seq TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- VERIFY:
-- SELECT market, active, registered_at, levels_json
--   FROM manuheadfund.partial_exit_ladders ORDER BY registered_at DESC LIMIT 20;
