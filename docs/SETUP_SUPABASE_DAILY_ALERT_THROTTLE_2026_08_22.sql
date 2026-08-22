-- SETUP_SUPABASE_DAILY_ALERT_THROTTLE_2026_08_22.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Achado real (2026-08-22): owner reportou "recebendo mensagem telegram pra
-- caramba" -- Test-DailyMarketAlertThrottle (lib_telegram.ps1, criada
-- 2026-08-15 exatamente pra limitar isso a 1 alerta/moeda/janela do dia)
-- persistia em journal/daily_alert_throttle.json, um arquivo LOCAL. Esse
-- arquivo cai na regra generica journal/*.json do .gitignore e nunca
-- sobrevive entre execucoes do GitHub Actions (cada job = checkout limpo,
-- processo PowerShell novo) -- o throttle resetava a zero a cada ciclo de
-- 5min, entao RENDERUSDT/BTCUSDT/INJUSDT (ja posicionados, bloqueados
-- corretamente pelo exposure cap) geravam um Telegram NOVO a cada ciclo,
-- indefinidamente. Mesma classe de bug ja corrigida no mesmo dia em
-- evolution_params.json (2026-08-21) e per_asset_whitelist_*.json.
--
-- key = "Market|Reason|date|window" (ex: "BTCUSDT|exposure_cap|2026-08-22|manha")
-- como PRIMARY KEY: upsert natural, 1 linha por combinacao, sobrevive entre
-- processos. lib_telegram.ps1 (Test-DailyMarketAlertThrottle) consulta esta
-- tabela quando disponivel, com fallback pro JSON local se Supabase falhar
-- (fail-open -- throttle e conveniencia, nunca bloqueia alerta real).

CREATE TABLE IF NOT EXISTS manuheadfund.daily_alert_throttle (
    key         TEXT PRIMARY KEY,
    count       INTEGER NOT NULL DEFAULT 1,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_daily_alert_throttle_updated ON manuheadfund.daily_alert_throttle(updated_at DESC);

ALTER TABLE manuheadfund.daily_alert_throttle ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE ON manuheadfund.daily_alert_throttle TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "daily_alert_throttle_all" ON manuheadfund.daily_alert_throttle;
CREATE POLICY "daily_alert_throttle_all" ON manuheadfund.daily_alert_throttle
    FOR ALL USING (true) WITH CHECK (true);

NOTIFY pgrst, 'reload schema';
