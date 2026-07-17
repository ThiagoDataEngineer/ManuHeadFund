-- SETUP_SUPABASE_GATE_REPLAY_STUDY_ADD_TORI_SCORE_2026_07_17.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- gate_replay_study ganhou uma 3a fonte de candidatos (scripts/gate_replay_study.ps1):
-- alem de top-movers sinteticos (score=65 fixo) e universo LIVE, agora tambem
-- simula os candidatos TORI_SHORT REAIS do tier_a_live (Test-ToriConfluence,
-- mesma funcao do sweep ao vivo em gem_loop.ps1), com o confluence_score real.
-- Precisamos da coluna tori_score pra poder separar depois (ex: confluence
-- 80-89 vs >=90, pra medir se vale baixar o piso do [PUMP GATE OVERRIDE]).
-- Sem essa coluna, Save-StateRecords (upsert) falha com PGRST204 (coluna
-- desconhecida no payload).

ALTER TABLE manuheadfund.gate_replay_study
    ADD COLUMN IF NOT EXISTS tori_score NUMERIC;

CREATE INDEX IF NOT EXISTS idx_gate_replay_tori_score
    ON manuheadfund.gate_replay_study(tori_score)
    WHERE tori_score IS NOT NULL;

-- VERIFY:
-- SELECT market, direction, tori_score, would_pass, blocked_by, returns
-- FROM manuheadfund.gate_replay_study
-- WHERE tori_score IS NOT NULL
-- ORDER BY ts DESC LIMIT 20;
