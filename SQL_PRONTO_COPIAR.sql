-- ============================================================================
-- COPIE TUDO ISTO E COLE NO SUPABASE SQL EDITOR
-- Depois clique RUN (botão azul)
-- Tempo: 5 segundos
-- ============================================================================

-- Table 1: capital_context
CREATE TABLE IF NOT EXISTS capital_context (
    id SERIAL PRIMARY KEY,
    asset VARCHAR(20) NOT NULL,
    strategy VARCHAR(50) NOT NULL,
    allocated_usd NUMERIC(12,2) NOT NULL,
    used_usd NUMERIC(12,2) DEFAULT 0,
    available_usd NUMERIC(12,2) GENERATED ALWAYS AS (allocated_usd - used_usd) STORED,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(asset, strategy),
    CHECK (allocated_usd > 0),
    CHECK (used_usd >= 0),
    CHECK (used_usd <= allocated_usd)
);

-- Table 2: cron_state
CREATE TABLE IF NOT EXISTS cron_state (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(50) NOT NULL UNIQUE,
    last_run TIMESTAMP,
    next_run TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',
    error_count INT DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_capital_context_asset_strategy ON capital_context(asset, strategy);
CREATE INDEX IF NOT EXISTS idx_capital_context_available ON capital_context(available_usd);
CREATE INDEX IF NOT EXISTS idx_cron_state_job_name ON cron_state(job_name);
CREATE INDEX IF NOT EXISTS idx_cron_state_status ON cron_state(status);
CREATE INDEX IF NOT EXISTS idx_cron_state_next_run ON cron_state(next_run);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON capital_context TO public;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron_state TO public;
GRANT USAGE ON SEQUENCE capital_context_id_seq TO public;
GRANT USAGE ON SEQUENCE cron_state_id_seq TO public;

-- Insert data
INSERT INTO capital_context (asset, strategy, allocated_usd) VALUES
    ('SPOT', 'gem_discovery', 300.00),
    ('FUTURES', 'gem_discovery', 200.00),
    ('FUTURES', 'scan_master', 100.00),
    ('FUTURES', 'scalp_engine', 150.00)
ON CONFLICT (asset, strategy) DO NOTHING;

INSERT INTO cron_state (job_name, status) VALUES
    ('gem_loop', 'pending'),
    ('scan_master', 'pending'),
    ('position_watcher', 'pending'),
    ('tg_listener', 'pending'),
    ('watchdog', 'pending'),
    ('grade_decision', 'pending'),
    ('evolution_tune', 'pending')
ON CONFLICT (job_name) DO NOTHING;
