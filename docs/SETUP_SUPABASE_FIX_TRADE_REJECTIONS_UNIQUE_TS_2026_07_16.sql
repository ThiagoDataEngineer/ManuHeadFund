-- Fix: trade_rejections.ts tinha so INDEX, nao UNIQUE constraint.
-- Save-StateRecords (Write-SignalSkip) usa -PrimaryKey "ts", que gera
-- ?on_conflict=ts no POST -- Postgres exige constraint UNIQUE/EXCLUSION real
-- pra isso funcionar, um indice comum nao basta.
--
-- Achado 2026-07-16: erro so apareceu APOS o fix do bug [ordered]@{} em
-- _Supabase-Save (commit 2331a6c) -- antes o payload malformado (colunas
-- erradas tipo "Count"/"Keys") nunca chegava a validar o ON CONFLICT de
-- verdade. Com o payload correto, o Postgres reclama:
-- 42P10 "there is no unique or exclusion constraint matching the ON
-- CONFLICT specification". Ou seja: trade_rejections NUNCA gravou com
-- sucesso desde a criacao da funcao (2026-06-09) -- 2 bugs empilhados
-- mascarando um ao outro.
--
-- Execute isso no Supabase Dashboard (schema manuheadfund, tabela ja
-- movida de public->manuheadfund em commit anterior, ver
-- SETUP_SUPABASE_FIX_TRADE_REJECTIONS_SCHEMA_2026_07_16.sql).

ALTER TABLE manuheadfund.trade_rejections
    ADD CONSTRAINT trade_rejections_ts_key UNIQUE (ts);

-- Verificacao
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'manuheadfund.trade_rejections'::regclass;
