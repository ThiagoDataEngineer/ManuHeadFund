-- docs/SETUP_SUPABASE_MINIMAL.sql
-- Minimal Supabase setup (tested, no errors)
-- Copy-paste this ENTIRE script into Supabase SQL Editor and Run

-- TABLE 1: trade_outcomes
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

CREATE INDEX IF NOT EXISTS idx_trade_symbol_ts ON manuheadfund.trade_outcomes(symbol, entry_ts DESC);
CREATE INDEX IF NOT EXISTS idx_trade_status ON manuheadfund.trade_outcomes(status);

-- TABLE 2: open_positions
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

CREATE INDEX IF NOT EXISTS idx_position_symbol ON manuheadfund.open_positions(symbol);
CREATE INDEX IF NOT EXISTS idx_position_status ON manuheadfund.open_positions(status);

-- TABLE 3: trailing_positions (Real-time sync)
CREATE TABLE IF NOT EXISTS manuheadfund.trailing_positions (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    direction TEXT NOT NULL,
    entry_price FLOAT8 NOT NULL,
    quantity FLOAT8 NOT NULL,
    current_price FLOAT8 DEFAULT 0,
    stop_loss_price FLOAT8 DEFAULT 0,
    take_profit_price FLOAT8 DEFAULT 0,
    trailing_stop_current FLOAT8,
    pnl_unrealized FLOAT8 DEFAULT 0,
    regime TEXT,
    phase TEXT,
    status TEXT DEFAULT 'active',
    entered_at TIMESTAMPTZ NOT NULL,
    last_sync_ts TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trailing_symbol ON manuheadfund.trailing_positions(symbol);
CREATE INDEX IF NOT EXISTS idx_trailing_status ON manuheadfund.trailing_positions(status);

-- TABLE 4: exchange_sync_log (Audit trail)
CREATE TABLE IF NOT EXISTS manuheadfund.exchange_sync_log (
    id BIGSERIAL PRIMARY KEY,
    sync_ts TIMESTAMPTZ DEFAULT now(),
    symbol TEXT,
    action TEXT NOT NULL,
    new_state JSONB,
    error TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sync_log_ts ON manuheadfund.exchange_sync_log(sync_ts DESC);

-- TABLE 5: daily_reconciliation (EOD summaries)
CREATE TABLE IF NOT EXISTS manuheadfund.daily_reconciliation (
    reconcile_date DATE PRIMARY KEY,
    total_trades_day INT DEFAULT 0,
    win_count INT DEFAULT 0,
    loss_count INT DEFAULT 0,
    pnl_realized FLOAT8 DEFAULT 0,
    regime TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE 6: agent_decisions (Decision audit trail)
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

CREATE INDEX IF NOT EXISTS idx_decisions_agent ON manuheadfund.agent_decisions(agent_name);
CREATE INDEX IF NOT EXISTS idx_decisions_created ON manuheadfund.agent_decisions(created_at DESC);

-- VERIFY: Run this SEPARATELY after all tables created
-- SELECT count(*) as table_count FROM information_schema.tables WHERE table_schema='manuheadfund';
-- Expected: 6+ tables (6 new + any from commit c67f25e)
