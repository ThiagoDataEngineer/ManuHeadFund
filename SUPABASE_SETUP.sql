INSERT INTO capital_context (strategy, allocated_usd) VALUES
    ('gem_discovery', 500.00),
    ('scan_master', 100.00),
    ('scalp_engine', 150.00)
ON CONFLICT (strategy) DO NOTHING;

INSERT INTO cron_state (job_name, status) VALUES
    ('gem_loop', 'pending'),
    ('scan_master', 'pending'),
    ('position_watcher', 'pending'),
    ('tg_listener', 'pending'),
    ('watchdog', 'pending'),
    ('grade_decision', 'pending'),
    ('evolution_tune', 'pending')
ON CONFLICT (job_name) DO NOTHING;
