-- SETUP_SUPABASE_LIVE_MONITOR_SNAPSHOTS_2026_07_20.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Fase 1 do PRD_LIVE_MONITOR_AUTOCORRECAO_2026_07_20.md: monitor de live
-- trading em 6 camadas (jobs, trades, rejeicoes, leverage real, schema
-- drift, rate limit). Read-only, sem auto-correcao ainda. Esta tabela
-- persiste 1 snapshot por ciclo do monitor, pra ter historico consultavel
-- (nao so o log do ultimo run do GitHub Actions).

CREATE TABLE IF NOT EXISTS manuheadfund.live_monitor_snapshots (
    id              BIGSERIAL PRIMARY KEY,
    ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
    ok_count        INT NOT NULL DEFAULT 0,
    warn_count      INT NOT NULL DEFAULT 0,
    critical_count  INT NOT NULL DEFAULT 0,
    findings        JSONB NOT NULL DEFAULT '[]',
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_live_monitor_ts ON manuheadfund.live_monitor_snapshots(ts DESC);
CREATE INDEX IF NOT EXISTS idx_live_monitor_critical ON manuheadfund.live_monitor_snapshots(critical_count) WHERE critical_count > 0;

GRANT SELECT, INSERT ON manuheadfund.live_monitor_snapshots TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE manuheadfund.live_monitor_snapshots_id_seq TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- VERIFY:
-- SELECT ts, ok_count, warn_count, critical_count, findings
--   FROM manuheadfund.live_monitor_snapshots ORDER BY ts DESC LIMIT 20;
