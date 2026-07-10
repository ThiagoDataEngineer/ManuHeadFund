-- ============================================================================
-- SQL SIMPLIFICADO — SEM COLUNA 'asset'
-- Copie e cole NO SUPABASE SQL EDITOR → RUN
-- Tempo: 5 segundos
-- ============================================================================

-- Table 1: capital_context
CREATE TABLE capital_context (
    id SERIAL PRIMARY KEY,
    strategy VARCHAR(50) NOT NULL UNIQUE,
    allocated_usd NUMERIC(12,2) NOT NULL,
    used_usd NUMERIC(12,2) DEFAULT 0,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    CHECK (allocated_usd > 0),
    CHECK (used_usd >= 0),
    CHECK (used_usd <= allocated_usd)
);

-- Table 2: cron_state
CREATE TABLE cron_state (
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
CREATE INDEX idx_capital_context_strategy ON capital_context(strategy);
CREATE INDEX idx_cron_state_job_name ON cron_state(job_name);
CREATE INDEX idx_cron_state_status ON cron_state(status);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON capital_context TO public;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron_state TO public;
GRANT USAGE ON SEQUENCE capital_context_id_seq TO public;
GRANT USAGE ON SEQUENCE cron_state_id_seq TO public;

-- Insert data
INSERT INTO capital_context (strategy, allocated_usd) VALUES
    ('gem_discovery', 500.00),
    ('scan_master', 100.00),
    ('scalp_engine', 150.00);

INSERT INTO cron_state (job_name, status) VALUES
    ('gem_loop', 'pending'),
    ('scan_master', 'pending'),
    ('position_watcher', 'pending'),
    ('tg_listener', 'pending'),
    ('watchdog', 'pending'),
    ('grade_decision', 'pending'),
    ('evolution_tune', 'pending');
