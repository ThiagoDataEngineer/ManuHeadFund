-- ============================================================================
-- SETUP_SUPABASE_MANUHEADFUND_2026_07_09.sql  (v2 — índices guardados)
-- Setup COMPLETO e ATUAL do ManuHeadFund no projeto Supabase novo.
--
-- ⚠️ ESCOPO: schema `manuheadfund` APENAS. NENHUMA linha toca o schema `public`
--    (onde vivem payments/shares/lnurl_* e tabelas de outras aplicações).
--    Tudo IF NOT EXISTS — idempotente, re-rodável, sem DROP, sem ALTER em nada
--    que já exista.
--
-- v2 fix (42703 "column market does not exist"): tabelas PRÉ-EXISTENTES no
-- projeto podem ter shape diferente (ex: trailing_positions com coluna symbol
-- em vez de market). CREATE TABLE IF NOT EXISTS pula a criação, mas CREATE
-- INDEX numa coluna ausente ESTOURA. Agora TODO índice é guardado por checagem
-- de existência da coluna — cria só se o shape bater.
--
-- Consolida (e SUBSTITUI para o projeto novo):
--   SUPABASE_STATE_SCHEMA.md Etapa 1 · SETUP_SUPABASE_LEARNING_2026_07_07.sql
--   SETUP_SUPABASE_CRON_STATE.sql · SETUP_SUPABASE_MINIMAL.sql
-- NÃO usar SETUP_SUPABASE_COMPLETO_2026_07_04.sql (cria em public — projeto antigo).
--
-- Pós-run: conferir Dashboard > Settings > API > "Exposed schemas" inclui
-- `manuheadfund` (já inclui, pois trailing_positions responde via REST).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS manuheadfund;
GRANT USAGE ON SCHEMA manuheadfund TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA manuheadfund GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA manuheadfund GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ── CORE STATE (lib_state_store) ─────────────────────────────────────────────

-- trailing_state: estado do trailing/Moon Bag (lib_trailing.ps1, shape pk_id/market)
-- 2026-07-09: RENOMEADA de trailing_positions — aquela pertence ao position_sync
-- (shape id/symbol). Dois shapes na mesma tabela = upsert 400 silencioso = estado
-- do trailing nunca persistia na nuvem (peaks/fases resetavam a cada run).
CREATE TABLE IF NOT EXISTS manuheadfund.trailing_state (
    pk_id            TEXT PRIMARY KEY,
    market           TEXT NOT NULL,
    side             TEXT NOT NULL,
    entry            NUMERIC NOT NULL,
    stop             NUMERIC NOT NULL,
    target           NUMERIC NOT NULL,
    size             NUMERIC,
    "orderId"        TEXT,
    source           TEXT,
    mode             TEXT,
    max_days         INTEGER DEFAULT 0,
    dd_threshold_pct NUMERIC DEFAULT 30,
    phase            INTEGER DEFAULT 0,
    peak             NUMERIC,
    "stopCurrent"    NUMERIC,
    active           BOOLEAN DEFAULT TRUE,
    "openedAt"       TEXT,
    "updatedAt"      TEXT,
    "currentPrice"   NUMERIC,
    "moonBagPairId"  TEXT,
    "moonBagKind"    TEXT,
    "layer4Advisory" TEXT,
    "layer4AdvisoryReason" TEXT,
    "lastLayer4Review"     TEXT,
    "moonBagAdvisory"      TEXT,
    "moonBagAdvisoryReason" TEXT,
    "lastMoonBagReview"    TEXT,
    "lastMentorReview"     TEXT,
    "entryRegime"          TEXT
);
CREATE INDEX IF NOT EXISTS idx_trailing_state_market ON manuheadfund.trailing_state (market);

-- 2026-07-23: coluna origin faltando -- codigo (commit a28d405, 2026-07-22)
-- passou a gravar Position.origin = {asset_class, trade_style} pro motor de
-- trailing unificado (lib_trailing_unified.ps1) parar de sempre dar SKIP
-- ("Position.origin.{asset_class,trade_style} e obrigatorio"), mas a coluna
-- nunca foi migrada aqui -- 12 erros PGRST204 por ciclo confirmados em
-- producao ("Could not find the 'origin' column"), Save-StateRecords cai
-- pro fallback local (perdido no proximo job, runner isolado) toda vez.
-- JSONB pq origin e sempre objeto aninhado {asset_class, trade_style}.
-- IMPORTANTE: esta mesma falha de escrita tambem explica "Posicoes ativas:
-- 1 / total 19" visto em Layer 2/4/5 -- Sync-TrailingPositionsWithExchange
-- tenta reativar registros (active=true) toda vez que sincroniza com a
-- exchange, mas a escrita falhava (mesmo PGRST204) e o campo active nunca
-- persistia atualizado. Rodar este ALTER TABLE deve corrigir os dois
-- sintomas ao mesmo tempo (mesma causa raiz, nao 2 bugs separados).
ALTER TABLE manuheadfund.trailing_state ADD COLUMN IF NOT EXISTS origin JSONB;
GRANT ALL ON manuheadfund.trailing_state TO anon, authenticated, service_role;

-- capital_context: snapshot do capital (single-row id=1) — ★ a que faltava (PGRST205)
CREATE TABLE IF NOT EXISTS manuheadfund.capital_context (
    id          INTEGER PRIMARY KEY DEFAULT 1,
    spot        NUMERIC NOT NULL,
    futures     NUMERIC NOT NULL,
    total       NUMERIC NOT NULL,
    snapshot_ts TEXT NOT NULL,
    source      TEXT NOT NULL
);

-- tori_proximity_state: snapshot single-row (id=1) do scanner de proximidade.
-- 2026-07-23: cada job GitHub Actions e um runner isolado (checkout proprio) --
-- o arquivo local journal/tori_proximity_state.json escrito pelo job "Tori
-- Proximity Scanner" nunca chegava no job "Gem Scanner+Executor", que por
-- isso sempre lia conviction=0 e travava no quality gate (blind_entry).
-- Mesmo padrao de capital_context: single-row, upsert por id, TTL no consumer.
CREATE TABLE IF NOT EXISTS manuheadfund.tori_proximity_state (
    id      INTEGER PRIMARY KEY DEFAULT 1,
    ts_utc  TEXT NOT NULL,
    markets TEXT NOT NULL
);
GRANT ALL ON manuheadfund.tori_proximity_state TO anon, authenticated, service_role;

-- entry_locks: lock distribuido de curta duracao (TTL) pra evitar race
-- condition entre os 3 motores de execucao real (gem_scanner_executor_live,
-- gem_loop, faro_v3_entry) tentando abrir o MESMO market ao mesmo tempo.
-- 2026-07-23: cada motor ja checa CoinEx-GetPendingPositions (exchange real)
-- antes de abrir, mas ha uma janela real entre esse check e o PlaceOrder --
-- 2 motores rodando em paralelo (jobs GH Actions distintos, sem lock
-- compartilhado) podem ambos ver "sem posicao" e tentar abrir ao mesmo tempo.
-- pk=market, expires_at curto (segundos) -- lock expira sozinho se o job
-- travar/crashar, nunca fica "preso" bloqueando o market indefinidamente.
CREATE TABLE IF NOT EXISTS manuheadfund.entry_locks (
    market      TEXT PRIMARY KEY,
    locked_by   TEXT NOT NULL,
    locked_at   TEXT NOT NULL,
    expires_at  TEXT NOT NULL
);
GRANT ALL ON manuheadfund.entry_locks TO anon, authenticated, service_role;

-- trailing_positions: estado trailing/Moon Bag (se já existe, mantém como está)
CREATE TABLE IF NOT EXISTS manuheadfund.trailing_positions (
    pk_id            TEXT PRIMARY KEY,
    market           TEXT NOT NULL,
    side             TEXT NOT NULL,
    entry            NUMERIC NOT NULL,
    stop             NUMERIC NOT NULL,
    target           NUMERIC NOT NULL,
    size             NUMERIC,
    "orderId"        TEXT,
    source           TEXT,
    mode             TEXT,
    max_days         INTEGER DEFAULT 0,
    dd_threshold_pct NUMERIC DEFAULT 30,
    phase            INTEGER DEFAULT 0,
    peak             NUMERIC,
    "stopCurrent"    NUMERIC,
    active           BOOLEAN DEFAULT TRUE,
    "openedAt"       TEXT,
    "updatedAt"      TEXT,
    "currentPrice"   NUMERIC,
    "moonBagPairId"  TEXT,
    "moonBagKind"    TEXT,
    "layer4Advisory" TEXT,
    "layer4AdvisoryReason" TEXT,
    "lastLayer4Review"     TEXT,
    "moonBagAdvisory"      TEXT,
    "moonBagAdvisoryReason" TEXT,
    "lastMoonBagReview"    TEXT,
    "lastMentorReview"     TEXT,
    "entryRegime"          TEXT
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='trailing_positions' AND column_name='market') THEN
    CREATE INDEX IF NOT EXISTS idx_trailing_market ON manuheadfund.trailing_positions (market);
  END IF;
END $$;

-- validation_snapshots: log de cada ciclo do scan_master
CREATE TABLE IF NOT EXISTS manuheadfund.validation_snapshots (
    id           BIGSERIAL PRIMARY KEY,
    snapshot_ts  TEXT NOT NULL,
    cycle        INTEGER,
    positions_n  INTEGER,
    payload      JSONB
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='validation_snapshots' AND column_name='snapshot_ts') THEN
    CREATE INDEX IF NOT EXISTS idx_validation_ts ON manuheadfund.validation_snapshots (snapshot_ts DESC);
  END IF;
END $$;

-- mentor_reviews: Layer 2 checkpoint reviews
CREATE TABLE IF NOT EXISTS manuheadfund.mentor_reviews (
    id           BIGSERIAL PRIMARY KEY,
    market       TEXT NOT NULL,
    review_ts    TEXT NOT NULL,
    decision     TEXT,
    reason       TEXT,
    confidence   NUMERIC,
    new_stop     NUMERIC,
    payload      JSONB
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='mentor_reviews' AND column_name='market') THEN
    CREATE INDEX IF NOT EXISTS idx_mentor_market_ts ON manuheadfund.mentor_reviews (market, review_ts DESC);
  END IF;
END $$;

-- ── TRADE JOURNAL (lib_trade_journal_supabase — formato ATUAL do writer) ─────

CREATE TABLE IF NOT EXISTS manuheadfund.trade_outcomes (
    id TEXT PRIMARY KEY,
    entry_ts TIMESTAMPTZ NOT NULL,
    symbol TEXT NOT NULL,
    direction TEXT NOT NULL,
    source TEXT NOT NULL,
    entry_price FLOAT8 NOT NULL,
    exit_price FLOAT8 DEFAULT 0,
    quantity FLOAT8 NOT NULL,
    pnl_realized FLOAT8 DEFAULT 0,
    pnl_percent FLOAT8 DEFAULT 0,
    status TEXT DEFAULT 'pending',
    regime TEXT,
    has_confluence BOOLEAN DEFAULT false,
    conviction_score FLOAT8,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='trade_outcomes' AND column_name='symbol') THEN
    CREATE INDEX IF NOT EXISTS idx_trade_symbol_ts ON manuheadfund.trade_outcomes(symbol, entry_ts DESC);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS manuheadfund.open_positions (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    direction TEXT NOT NULL,
    entry_price FLOAT8 NOT NULL,
    quantity FLOAT8 NOT NULL,
    stop_loss FLOAT8 DEFAULT 0,
    take_profit FLOAT8 DEFAULT 0,
    current_price FLOAT8 DEFAULT 0,
    trailing_stop FLOAT8,
    pnl_unrealized FLOAT8 DEFAULT 0,
    source TEXT NOT NULL,
    regime TEXT,
    status TEXT DEFAULT 'active',
    entered_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='open_positions' AND column_name='symbol') THEN
    CREATE INDEX IF NOT EXISTS idx_position_symbol ON manuheadfund.open_positions(symbol);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS manuheadfund.exchange_sync_log (
    id BIGSERIAL PRIMARY KEY,
    sync_ts TIMESTAMPTZ DEFAULT now(),
    symbol TEXT,
    action TEXT NOT NULL,
    new_state JSONB,
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS manuheadfund.daily_reconciliation (
    reconcile_date DATE PRIMARY KEY,
    total_trades_day INT DEFAULT 0,
    win_count INT DEFAULT 0,
    loss_count INT DEFAULT 0,
    pnl_realized FLOAT8 DEFAULT 0,
    regime TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS manuheadfund.agent_decisions (
    id BIGSERIAL PRIMARY KEY,
    agent_name TEXT NOT NULL,
    decision_type TEXT NOT NULL,
    symbol TEXT,
    direction TEXT,
    conviction FLOAT8,
    confidence FLOAT8,
    reasoning JSONB,
    outcome TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    decided_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT now()
);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='manuheadfund' AND table_name='agent_decisions' AND column_name='created_at') THEN
    CREATE INDEX IF NOT EXISTS idx_decisions_created ON manuheadfund.agent_decisions(created_at DESC);
  END IF;
END $$;

-- ── CÉREBRO EVOLUTIVO (learning — SETUP_SUPABASE_LEARNING_2026_07_07) ────────

CREATE TABLE IF NOT EXISTS manuheadfund.learned_multipliers (
    key          TEXT PRIMARY KEY,
    source       TEXT,
    direction    TEXT,
    regime       TEXT,
    n            INTEGER,
    wins         INTEGER,
    win_rate     NUMERIC,
    avg_pnl_pct  NUMERIC,
    sum_pnl      NUMERIC,
    reliable     BOOLEAN,
    updated_at   TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS manuheadfund.evolution_params (
    id                    TEXT PRIMARY KEY,
    sentinel_move_pct     NUMERIC,
    sentinel_ignition_pct NUMERIC,
    pumpfade_min_pump_pct NUMERIC,
    pumpfade_dump_pct     NUMERIC,
    gem_sizing_pct        NUMERIC,
    updated_at            TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS manuheadfund.evolution_history (
    ts       TEXT PRIMARY KEY,
    param    TEXT,
    before   NUMERIC,
    after    NUMERIC,
    reason   TEXT
);

CREATE TABLE IF NOT EXISTS manuheadfund.mce_counterfactual_agg (
    "group"      TEXT PRIMARY KEY,
    regime       TEXT,
    direction    TEXT,
    n            INTEGER,
    hit_rate     NUMERIC,
    avg_fwd_24h  NUMERIC,
    avg_fwd_72h  NUMERIC,
    updated_at   TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS manuheadfund.decision_grades_agg (
    key          TEXT PRIMARY KEY,
    decision     TEXT,
    direction    TEXT,
    regime       TEXT,
    n            INTEGER,
    correct_rate NUMERIC,
    avg_move_dir NUMERIC,
    updated_at   TIMESTAMPTZ
);

-- calibration_snapshots: registro do momento das calibracoes (lib_calibration_snapshot)
CREATE TABLE IF NOT EXISTS manuheadfund.calibration_snapshots (
    id      TEXT PRIMARY KEY,   -- data (dedup diario)
    ts      TEXT,
    regime  TEXT,
    payload TEXT
);
GRANT ALL ON manuheadfund.calibration_snapshots TO anon, authenticated, service_role;

-- ── CRON DEDUP (SETUP_SUPABASE_CRON_STATE) ───────────────────────────────────

CREATE TABLE IF NOT EXISTS manuheadfund.cron_state (
    job_id       TEXT PRIMARY KEY,
    last_run_utc TIMESTAMPTZ NOT NULL,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── GRANTS FINAIS (cobre tabelas criadas agora e as pré-existentes) ──────────

GRANT ALL ON ALL TABLES    IN SCHEMA manuheadfund TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA manuheadfund TO anon, authenticated, service_role;

-- ── VERIFICAÇÃO ──────────────────────────────────────────────────────────────
-- 1) Tabelas do schema (espere 15+):
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'manuheadfund' ORDER BY table_name;

-- 2) DIAGNÓSTICO shape da trailing_positions pré-existente (o 42703 provou que
--    ela NÃO tem coluna market — precisamos saber o shape real p/ alinhar o código):
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'manuheadfund' AND table_name = 'trailing_positions'
ORDER BY ordinal_position;
