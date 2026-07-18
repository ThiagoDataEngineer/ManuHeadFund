-- SETUP_SUPABASE_FIX_MCE_GATE_2026_07_17.sql
-- Corrige 2 schema drifts que bloqueavam silenciosamente o Evolution Engine
-- (agents/lib_evolution_engine.ps1) na cloud (Learning Cycle job, 2026-07-17
-- ~19:42 run, ver logs "WARNING: [state_store] Supabase ... failed").
--
-- (1) PGRST/42703 "column mce_counterfactual_agg.gate does not exist".
-- scripts/mce_counterfactual_from_supabase.ps1 passou a agregar tambem por
-- gate (nao so regime|direction) para alimentar a Regra C do Evolution Engine
-- (auto-ajuste de tori_confluence_threshold). A tabela real no Supabase nunca
-- recebeu a coluna nova -- toda leitura falha com 42703, entao a regra nunca
-- teve dado (n=0 sempre, fail-safe correto mas sem efeito pratico).

ALTER TABLE manuheadfund.mce_counterfactual_agg
    ADD COLUMN IF NOT EXISTS gate TEXT;

-- (2) PGRST204 "Could not find the 'faro_signals_needed' column of
-- 'evolution_params' in the schema cache". A tabela evolution_params e um
-- singleton (id='current') com 1 coluna por parametro tunavel de
-- Get-TunableRegistry -- foi criada antes do registro crescer para 10
-- parametros. Adiciona TODAS as colunas do registro atual (nao so a que
-- apareceu no log) para nao repetir este mesmo bug no proximo parametro
-- novo que o registro ganhar.

ALTER TABLE manuheadfund.evolution_params
    ADD COLUMN IF NOT EXISTS sentinel_move_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS sentinel_ignition_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pumpfade_min_pump_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS pumpfade_dump_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS tori_confluence_threshold DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS faro_signals_needed DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS gem_sizing_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS stop_atr_multiplier DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS gem_max_exposure_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS trailing_be_buffer_pct DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Notifica o PostgREST pra recarregar o schema cache (mesmo padrao usado no
-- incidente trailing_state/closeReason de 2026-07-14 -- NOTIFY sozinho pode
-- nao bastar; se a leitura ainda falhar apos este job, reiniciar o PostgREST
-- manualmente via Supabase Dashboard).
NOTIFY pgrst, 'reload schema';
