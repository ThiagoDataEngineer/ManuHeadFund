-- ============================================================================
-- TIER 1 FIX: Create missing tables (Bug #6, #7)
-- ============================================================================
-- Purpose: Enable autonomous 24/7 trading without capital context / cron failures
-- Tables: capital_context, cron_state
-- Grants: public (all authenticated users can access)
-- ============================================================================

-- Table 1: capital_context (Bug #6)
-- Tracks capital allocation per asset/strategy
-- Used by: gem_executor (leverage calc), mesa (position limits)
CREATE TABLE IF NOT EXISTS capital_context (
    id SERIAL PRIMARY KEY,
    asset VARCHAR(20) NOT NULL,          -- "BTC", "ETH", "FUTURES", etc
    strategy VARCHAR(50) NOT NULL,       -- "gem_discovery", "scan_master", etc
    allocated_usd NUMERIC(12,2) NOT NULL,  -- Total capital allocated
    used_usd NUMERIC(12,2) DEFAULT 0,      -- Currently in use
    available_usd NUMERIC(12,2) GENERATED ALWAYS AS (allocated_usd - used_usd) STORED,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(asset, strategy),
    CHECK (allocated_usd > 0),
    CHECK (used_usd >= 0),
    CHECK (used_usd <= allocated_usd)
);

-- Table 2: cron_state (Bug #7)
-- Tracks scheduled job execution state
-- Used by: gem_loop, scan_master, position_watcher (recovery detection)
CREATE TABLE IF NOT EXISTS cron_state (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(50) NOT NULL UNIQUE,  -- "gem_loop", "scan_master", etc
    last_run TIMESTAMP,                    -- When job last ran
    next_run TIMESTAMP,                    -- When job should run next
    status VARCHAR(20) DEFAULT 'pending',  -- pending, running, success, error
    error_count INT DEFAULT 0,             -- Consecutive errors
    last_error TEXT,                       -- Last error message
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_capital_context_asset_strategy ON capital_context(asset, strategy);
CREATE INDEX IF NOT EXISTS idx_capital_context_available ON capital_context(available_usd);
CREATE INDEX IF NOT EXISTS idx_cron_state_job_name ON cron_state(job_name);
CREATE INDEX IF NOT EXISTS idx_cron_state_status ON cron_state(status);
CREATE INDEX IF NOT EXISTS idx_cron_state_next_run ON cron_state(next_run);

-- Grants: Allow public (authenticated role) to SELECT/INSERT/UPDATE/DELETE
GRANT SELECT, INSERT, UPDATE, DELETE ON capital_context TO public;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron_state TO public;
GRANT USAGE ON SEQUENCE capital_context_id_seq TO public;
GRANT USAGE ON SEQUENCE cron_state_id_seq TO public;

-- Initialization: Insert default capital allocation (all strategies)
INSERT INTO capital_context (asset, strategy, allocated_usd) VALUES
    ('SPOT', 'gem_discovery', 300.00),
    ('FUTURES', 'gem_discovery', 200.00),
    ('FUTURES', 'scan_master', 100.00),
    ('FUTURES', 'scalp_engine', 150.00)
ON CONFLICT (asset, strategy) DO NOTHING;

-- Initialization: Insert default cron jobs
INSERT INTO cron_state (job_name, status) VALUES
    ('gem_loop', 'pending'),
    ('scan_master', 'pending'),
    ('position_watcher', 'pending'),
    ('tg_listener', 'pending'),
    ('watchdog', 'pending'),
    ('grade_decision', 'pending'),
    ('evolution_tune', 'pending')
ON CONFLICT (job_name) DO NOTHING;

-- ============================================================================
-- VERIFICATION QUERIES (run after applying this SQL)
-- ============================================================================

-- Verify tables exist and are accessible
-- SELECT * FROM capital_context;
-- SELECT * FROM cron_state;

-- Check grants
-- SELECT grantee, privilege_type FROM role_table_grants WHERE table_name IN ('capital_context', 'cron_state');
