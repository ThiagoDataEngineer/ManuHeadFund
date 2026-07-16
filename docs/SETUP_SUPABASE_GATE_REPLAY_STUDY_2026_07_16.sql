-- SETUP_SUPABASE_GATE_REPLAY_STUDY_2026_07_16.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Estudo ativo: pega top movers reais da CoinEx (nao depende do scanner ja
-- ter avaliado), simula os thresholds/gates ATUAIS via Invoke-GemExecute
-- -DryRun (fiel, gates reais incluindo Tori/LLM), grava snapshot inicial,
-- e revisita em multiplos horizontes curtos (10min/30min/1h/4h) pra medir
-- "o que teria acontecido" -- avaliando os DOIS sentidos: threshold
-- bloqueou e teria dado certo (falso negativo) vs threshold bloqueou e
-- teria dado errado (acerto). Complementa mce_counterfactual_agg (que so
-- mede sinais que JA passaram pelo gem_executor de verdade, horizontes
-- 24h/72h) com um estudo mais amplo e de scalp/gema (10min-4h).

CREATE TABLE IF NOT EXISTS manuheadfund.gate_replay_study (
    id              BIGSERIAL PRIMARY KEY,
    market          TEXT NOT NULL,
    direction       TEXT NOT NULL,              -- LONG | SHORT (simulado, do movimento observado)
    ts              TIMESTAMPTZ NOT NULL,        -- momento do snapshot inicial
    entry_price     NUMERIC NOT NULL,
    change_24h_pct  NUMERIC,                     -- % de variacao 24h no momento do snapshot (por que foi "top mover")
    regime          TEXT,                        -- cenario BTC no momento (BULL/BEAR/NEUTRO/etc)
    would_pass      BOOLEAN NOT NULL,             -- Invoke-GemExecute -DryRun: teria passado de TODAS as gates?
    blocked_by      TEXT,                        -- se bloqueado, motivo (mesmo formato de blocked_by do gem_executor)
    gates_snapshot  JSONB,                        -- detalhe completo: breadth/pump/tori/quality (auditoria)
    returns         JSONB NOT NULL DEFAULT '{}',  -- preenchido progressivamente: {"10m": 1.2, "30m": -0.5, "1h": null, "4h": null}
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_gate_replay_ts ON manuheadfund.gate_replay_study(ts DESC);
CREATE INDEX IF NOT EXISTS idx_gate_replay_market ON manuheadfund.gate_replay_study(market);
CREATE INDEX IF NOT EXISTS idx_gate_replay_would_pass ON manuheadfund.gate_replay_study(would_pass);

-- VERIFY:
-- SELECT market, direction, would_pass, blocked_by, returns FROM manuheadfund.gate_replay_study ORDER BY ts DESC LIMIT 20;
