-- SETUP_SUPABASE_TRAILING_SLTP_SOURCE_2026_08_06.sql
-- Achado CRITICO (2026-08-06): agents/lib_trailing.ps1 (Add-TrailingPosition)
-- grava sl_source/tp_source/stop_pct_used desde o commit 2c20d71 (2026-08-04,
-- instrumentacao pro Evolution Engine medir origem do SL/TP), mas a coluna
-- NUNCA foi criada na tabela real do Supabase -- toda escrita em
-- trailing_state falha com PGRST204 "Could not find the 'sl_source' column".
--
-- Isso nao e so um erro cosmetico: Save-TrailingPositions cai no catch e usa
-- fallback de ARQUIVO LOCAL (agents/lib_trailing.ps1 linha ~148), que em
-- producao real (GitHub Actions, workspace efemero) NAO sobrevive entre
-- jobs -- confirmado real: SOONUSDT/PIPPINUSDT (posicoes orfas re-detectadas
-- a cada ciclo, "pk_id duplicado" no log) nunca persistem no Supabase,
-- entao o proximo ciclo do trailing_stop_monitor.ps1 nunca as encontra via
-- Get-TrailingPositions (que le do Supabase), nunca entram no bloco
-- "TRAILING UNIFIED (ATIVO)" -- SL/TP delas fica congelado no valor de
-- abertura pra sempre, so o "peak" (preco de pico) e atualizado. Owner
-- reportou via screenshot real (SOONUSDT com TP/SL identico ao valor de
-- abertura, horas depois).
--
-- Mesmo padrao SQL+script+job ja validado nesta sessao (birth_score,
-- partial_exit_ladders).

ALTER TABLE manuheadfund.trailing_state
    ADD COLUMN IF NOT EXISTS sl_source      TEXT,
    ADD COLUMN IF NOT EXISTS tp_source      TEXT,
    ADD COLUMN IF NOT EXISTS stop_pct_used  NUMERIC;

NOTIFY pgrst, 'reload schema';
