# FARO V3 Aggressive Config — Deployed 2026-06-02
# Changes from conservative (score 35) to aggressive (score 28)

$global:FARO_CONFIG = @{
    # Scoring threshold
    score_threshold_aggressive = 28   # was: 35
    score_threshold_conservative = 35

    # Signal requirements
    min_signals_required = 4          # was: 5 (now WATCH decision acceptable)
    signal_definition = @{
        momentum = "volume ROC"
        pattern = "Wyckoff spring + bull pennant"
        sentiment = "onchain whale"
        entry_timing = "Livermore breakout"
        whale_flow = "exchange accumulation"
        ml_confidence = "gradient boosting"
        margin_safety = "liquidation risk"
    }

    # Volume filter
    min_volume_ratio = 1.0            # was: 1.5x (now capture ALL micro-caps)
    target_vol_usd_min = 0            # no minimum USD volume

    # Daily constraints
    daily_gem_cap = 5                 # was: 3
    max_exposure_usd = 150            # ~$30/gem * 5
    max_gems_per_week = 35            # rolling window

    # Risk per gem
    risk_pct_per_gem = @{
        faro = 0.4                    # gem: 0.4% capital
        standard = 0.5                # standard trades: 0.5%
        tier_a = 1.0                  # tier A: 1.0%
    }

    # Paper calibration (while BEAR_WEAK)
    mode = "PAPER"                    # LIVE after 1 week validation
    paper_score_minimo = 55           # score filter in journal
    paper_cycle_interval_min = 30     # every 30 min

    # Backtest validation results
    backtest_verdict = @{
        historical_pumps_captured = 4
        recall_at_28 = 1.0
        recall_at_35 = 1.0
        precision_at_28 = 0.67        # 4/(4+2 noise)
        expected_false_pos_per_week = 2
        alpha_loss = "NONE"
    }

    # Deploy timestamp
    deployed_at = "2026-06-02T22:15:00Z"
    deployed_by = "Claude Haiku 4.5"
    commit = "4e91e02"
}

Write-Host "✅ FARO Aggressive config loaded" -ForegroundColor Green
Write-Host "   Score threshold: $($global:FARO_CONFIG.score_threshold_aggressive)" -ForegroundColor Cyan
Write-Host "   Daily cap: $($global:FARO_CONFIG.daily_gem_cap) gems/day" -ForegroundColor Cyan
Write-Host "   Mode: $($global:FARO_CONFIG.mode)" -ForegroundColor Cyan
