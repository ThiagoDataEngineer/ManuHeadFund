-- SETUP_SUPABASE_FIX_TRADE_REJECTIONS_SCHEMA_2026_07_16.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- CAUSA RAIZ (investigada 2026-07-16): trade_rejections foi criada em
-- public.trade_rejections (docs/SETUP_SUPABASE_SIGNAL_SKIPS.sql, 2026-06-09).
-- Mas lib_state_store.ps1 usa schema "manuheadfund" por padrao desde
-- 2026-06-28 (fix de outro incidente: schema "public" e compartilhado com
-- outro app, causou colisao de tabela). Todo Get-StateRecords/Save-StateRecords
-- manda header Accept-Profile/Content-Profile: manuheadfund -- procura
-- manuheadfund.trade_rejections, que nao existe, retorna PGRST205
-- ("nao encontrada" -- tecnicamente correto, so aponta schema errado).
--
-- O job "Initialize Data (Supabase) > Create trade_rejections Table" (que
-- faz INSERT direto via Invoke-RestMethod, sem esses headers de profile)
-- sempre reportou "OK" porque mira public implicitamente -- por isso
-- pareceu que a tabela "existia" enquanto o resto do sistema (Write-SignalSkip,
-- MCE Counterfactual job) via ela como ausente.
--
-- FIX: move a tabela existente pra manuheadfund (schema usado por TODAS as
-- outras tabelas do projeto -- trade_outcomes, trailing_state, etc, ja
-- confirmadas funcionando). Preserva dados, indices, tudo -- so muda o
-- namespace. Reversivel (ALTER TABLE ... SET SCHEMA public desfaz).

ALTER TABLE public.trade_rejections SET SCHEMA manuheadfund;

-- VERIFY (rodar depois, deve retornar a tabela em manuheadfund):
-- SELECT table_schema, table_name FROM information_schema.tables WHERE table_name = 'trade_rejections';
