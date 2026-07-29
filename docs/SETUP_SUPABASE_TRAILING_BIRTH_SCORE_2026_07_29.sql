-- SETUP_SUPABASE_TRAILING_BIRTH_SCORE_2026_07_29.sql
-- Achado (2026-07-29): owner pediu avaliacao real de "quanto cada sinal
-- previa ganhar e em quanto tempo". gem_executor.ps1 ja calculava o "score
-- de nascimento" ($__birthScore = conviction ensemble + bonus eixos fortes
-- + bonus/penalidade FQS) desde 2026-07-27, mas Add-TrailingPosition
-- (lib_trailing.ps1) NUNCA persistia esse dado em trailing_state -- so
-- aparecia no log de texto do run, perdido apos a retencao do GitHub Actions.
--
-- Fix real: agents/lib_trailing.ps1 agora grava 3 colunas novas no objeto
-- $pos salvo via Save-StateRecords. Roda uma vez via workflow_dispatch
-- (job apply-trailing-birth-score-schema), mesmo padrao SQL+script+job
-- ja validado nesta sessao (mentor_shadow_observations, decision_reflections).

ALTER TABLE manuheadfund.trailing_state
    ADD COLUMN IF NOT EXISTS birth_score        NUMERIC,
    ADD COLUMN IF NOT EXISTS birth_mesa_sinal    TEXT,
    ADD COLUMN IF NOT EXISTS birth_fqs_category  TEXT;

NOTIFY pgrst, 'reload schema';
