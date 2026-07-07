-- ============================================================================
-- SETUP_SUPABASE_LEARNING_2026_07_07.sql
-- Espelho do "cerebro evolutivo" (auto-aprendizado dos agentes) no schema
-- ISOLADO manuheadfund. Sem isto, o aprendizado morre no reboot e NAO existe
-- pro runner da nuvem (GitHub Actions roda em Linux, sem journal/ local).
--
-- ESCOPO: schema manuheadfund APENAS. Nenhuma outra app e tocada. CREATE ... IF
-- NOT EXISTS, nenhum DROP. Rode no Supabase Dashboard (SQL Editor).
--
-- O state store manda Content-Profile: manuheadfund (lib_state_store.ps1:86,122).
-- PK = coluna de on_conflict usada no upsert (merge-duplicates) do _Supabase-Save.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS manuheadfund;

-- ── 1. learned_multipliers ── agregado por chave source|direction|regime.
-- Consumido por Triagem/scan_master p/ ponderar LONG vs SHORT na ENTRADA.
CREATE TABLE IF NOT EXISTS manuheadfund.learned_multipliers (
    key          TEXT PRIMARY KEY,      -- "source|direction|regime"
    source       TEXT,
    direction    TEXT,
    regime       TEXT,
    n            INTEGER,
    wins         INTEGER,
    win_rate     NUMERIC,
    avg_pnl_pct  NUMERIC,
    sum_pnl      NUMERIC,
    reliable     BOOLEAN,
    updated_at   TIMESTAMPTZ
);

-- ── 2. evolution_params ── overlay corrente (singleton id="current").
-- Consumido por scan_master/sentinel_movers a cada ciclo (thresholds pump/dump/sizing).
CREATE TABLE IF NOT EXISTS manuheadfund.evolution_params (
    id                    TEXT PRIMARY KEY,   -- sempre "current"
    sentinel_move_pct     NUMERIC,
    sentinel_ignition_pct NUMERIC,
    pumpfade_min_pump_pct NUMERIC,
    pumpfade_dump_pct     NUMERIC,
    gem_sizing_pct        NUMERIC,
    updated_at            TIMESTAMPTZ
);

-- ── 3. evolution_history ── 1 linha por mudanca de parametro (auditoria da evolucao).
CREATE TABLE IF NOT EXISTS manuheadfund.evolution_history (
    ts       TEXT PRIMARY KEY,          -- ISO-8601 UTC do ajuste (unico por mudanca)
    param    TEXT,
    before   NUMERIC,
    after    NUMERIC,
    reason   TEXT
);

-- ── 4. mce_counterfactual_agg ── agregado por regime|direction (aprendizado "e se").
CREATE TABLE IF NOT EXISTS manuheadfund.mce_counterfactual_agg (
    "group"      TEXT PRIMARY KEY,       -- "regime|direction"
    regime       TEXT,
    direction    TEXT,
    n            INTEGER,
    hit_rate     NUMERIC,                -- % com fwd_return_24h > 0
    avg_fwd_24h  NUMERIC,
    avg_fwd_72h  NUMERIC,
    updated_at   TIMESTAMPTZ
);

-- ── 5. decision_grades_agg ── agregado por decision|direction|regime (calibracao LLM).
CREATE TABLE IF NOT EXISTS manuheadfund.decision_grades_agg (
    key          TEXT PRIMARY KEY,       -- "decision|direction|regime"
    decision     TEXT,
    direction    TEXT,
    regime       TEXT,
    n            INTEGER,
    correct_rate NUMERIC,                -- accuracy = correct/n
    avg_move_dir NUMERIC,
    updated_at   TIMESTAMPTZ
);

-- ── Grants: PostgREST usa service_role (o state store manda service key). ──
-- Consistente com as tabelas manuheadfund existentes (RLS off, acesso via service_role).
GRANT USAGE ON SCHEMA manuheadfund TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA manuheadfund TO service_role;

-- Expor o schema no PostgREST (se ainda nao estiver em db-schema):
--   Dashboard > Settings > API > Exposed schemas: incluir "manuheadfund".
-- (as tabelas manuheadfund ja existentes indicam que ja esta exposto.)
