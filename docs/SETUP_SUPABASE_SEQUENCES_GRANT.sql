-- ============================================================================
-- FIX: permission denied for sequence (Postgres 42501) em INSERTs no schema
-- manuheadfund. Descoberto 2026-06-20 ao ligar o espelho de trade_outcomes:
--
--   {"code":"42501","message":"permission denied for sequence trade_outcomes_id_seq"}
--
-- Causa: o schema setup (docs/SUPABASE_STATE_SCHEMA.md) deu
--   ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES
-- mas NAO concedeu USAGE nas SEQUENCES. Tabelas com BIGSERIAL (trade_outcomes,
-- validation_snapshots, mentor_reviews) precisam de USAGE na sequence do id
-- para inserir. Sem isso, todo INSERT via REST (anon/service_role) falha com 42501
-- e o espelho cai no warning (best-effort) -> 0 rows no Supabase.
--
-- Aplicar UMA vez no Supabase SQL Editor.
-- ============================================================================

-- 1. Sequences que ja existem
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA manuheadfund
    TO anon, authenticated, service_role;

-- 2. Sequences futuras (novas tabelas BIGSERIAL nao quebram de novo)
ALTER DEFAULT PRIVILEGES IN SCHEMA manuheadfund
    GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated, service_role;

-- Verificacao (opcional): deve listar as sequences com privilegios
-- SELECT sequence_schema, sequence_name
-- FROM information_schema.sequences
-- WHERE sequence_schema = 'manuheadfund';
