-- SETUP_SUPABASE_LLM_USAGE_2026_07_30.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Achado real (2026-07-30): Track-ClaudeUsage (agents/lib_cost_tracker.ps1) ja
-- e chamada de verdade em toda chamada de LLM (Claude/Groq/Mistral/Cerebras/
-- Gemini), mas grava num CSV LOCAL (journal/claude_usage.csv) -- arquivo que o
-- GitHub Actions apaga a cada job (runner efemero, mesma classe de bug ja
-- documentada em gem_position_events/trade_outcomes). Resultado: nenhum
-- historico real de custo jamais acumulava, e Send-CostAlarmTelegram/
-- Test-CostAlarmThreshold (tambem prontos, nunca conectados) nunca tinham
-- dado suficiente pra disparar nada util. Owner pediu visibilidade real de
-- onde o gasto de LLM esta indo ("torneira que so sai e nao entra nada").
--
-- Tabela nova e dedicada: registra CADA chamada real de LLM, persistida no
-- Supabase (sobrevive entre runs).

CREATE TABLE IF NOT EXISTS manuheadfund.llm_usage (
    id            BIGSERIAL PRIMARY KEY,
    ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
    agent         TEXT NOT NULL,   -- mentor | mesa_termal | mesa_radar | mesa_lidar | triagem | tech | fund | sent | chain
    model         TEXT NOT NULL,   -- ex: claude-sonnet-5, groq:llama-3.3-70b-versatile, mistral:mistral-small-latest
    input_tokens  INT NOT NULL DEFAULT 0,
    output_tokens INT NOT NULL DEFAULT 0,
    cost_usd      NUMERIC NOT NULL DEFAULT 0,
    latency_ms    NUMERIC,
    created_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_llm_usage_ts ON manuheadfund.llm_usage(ts DESC);
CREATE INDEX IF NOT EXISTS idx_llm_usage_agent ON manuheadfund.llm_usage(agent);
CREATE INDEX IF NOT EXISTS idx_llm_usage_model ON manuheadfund.llm_usage(model);

GRANT SELECT, INSERT ON manuheadfund.llm_usage TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE manuheadfund.llm_usage_id_seq TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- VERIFY:
-- SELECT agent, model, count(*) calls, sum(cost_usd) total_cost
--   FROM manuheadfund.llm_usage
--   WHERE ts > now() - interval '24 hours'
--   GROUP BY agent, model ORDER BY total_cost DESC;
