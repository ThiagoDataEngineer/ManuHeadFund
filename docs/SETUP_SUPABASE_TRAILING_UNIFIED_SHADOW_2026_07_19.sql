-- SETUP_SUPABASE_TRAILING_UNIFIED_SHADOW_2026_07_19.sql
-- Execute isso no Supabase Dashboard (SQL Editor)
--
-- Motor unico de trailing (lib_trailing_unified.ps1, Resolve-TrailingDecision)
-- roda em SHADOW MODE desde 2026-07-18 dentro de trailing_stop_monitor.ps1,
-- mas so grava a comparacao via Write-CrossPlatformLog -- arquivo local do
-- runner efemero do GitHub Actions, perdido a cada ciclo (~5-40min). Depois
-- de 1 dia "em shadow" nao havia NENHUM dado consultavel pra provar se o
-- motor unico (ATR real + exhaustion-aware) se comporta melhor que os 3
-- motores concorrentes atuais (lib_trailing_adaptive.ps1 com ATR fake fixo
-- em 100.0, lib_trailing_stop_intelligent.ps1, lib_trailing_sync.ps1) antes
-- de promover pra producao real. Esta tabela persiste cada decisao shadow
-- pra permitir consultar N dias de historico antes de decidir promover.
--
-- Contexto do achado (Oracle Bug #16): layer1-trailing-adaptive e
-- trailing-stop-monitor rodam ambos a cada ~5min via GitHub Actions, em
-- runners distintos sem lock entre si, podendo escrever SL diferente pra
-- mesma posicao na mesma janela.

CREATE TABLE IF NOT EXISTS manuheadfund.trailing_unified_shadow (
    id                BIGSERIAL PRIMARY KEY,
    market            TEXT NOT NULL,
    side              TEXT NOT NULL,              -- LONG | SHORT
    ts                TIMESTAMPTZ NOT NULL DEFAULT now(),
    real_stop          NUMERIC NOT NULL,            -- stopCurrent hoje (motores concorrentes atuais)
    unified_action    TEXT NOT NULL,               -- HOLD | UPDATE
    unified_new_stop  NUMERIC,                      -- new_stop sugerido pelo motor unico (null se HOLD)
    exhaustion_score  INT,
    atr_pct           NUMERIC,
    trailing_pct      NUMERIC,
    reason            TEXT,                        -- motivo da decisao (trail_normal, exhaustion_alto_aperta_forte, etc)
    would_have_differed BOOLEAN NOT NULL DEFAULT false,  -- unified_new_stop != real_stop (comparacao direta)
    created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trailing_unified_shadow_ts ON manuheadfund.trailing_unified_shadow(ts DESC);
CREATE INDEX IF NOT EXISTS idx_trailing_unified_shadow_market ON manuheadfund.trailing_unified_shadow(market);
CREATE INDEX IF NOT EXISTS idx_trailing_unified_shadow_differed ON manuheadfund.trailing_unified_shadow(would_have_differed);

GRANT SELECT, INSERT ON manuheadfund.trailing_unified_shadow TO anon, authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE manuheadfund.trailing_unified_shadow_id_seq TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- VERIFY:
-- SELECT market, side, real_stop, unified_action, unified_new_stop, exhaustion_score, reason, ts
--   FROM manuheadfund.trailing_unified_shadow ORDER BY ts DESC LIMIT 20;
--
-- Depois de alguns dias, pra decidir promover:
-- SELECT market, count(*) total, sum(CASE WHEN would_have_differed THEN 1 ELSE 0 END) diferiu
--   FROM manuheadfund.trailing_unified_shadow GROUP BY market ORDER BY total DESC;
