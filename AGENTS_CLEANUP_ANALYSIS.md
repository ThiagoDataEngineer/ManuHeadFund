# 🔍 Agents Folder Cleanup Analysis

**Date:** June 1, 2026  
**Status:** Analysis of 157 files - Identifying what's REALLY used vs garbage

---

## 📊 Current State

**Total Files in /agents:** 157 .ps1 files  
**Files Actually Loaded:** ~50 files  
**Unused/Garbage Files:** ~107 files (68%)

---

## ✅ ACTIVELY USED FILES (Must Keep)

### Core Configuration (3)
- `config.ps1` - Main configuration
- `config.local.ps1` - Local secrets (Supabase, API keys)
- `config.telegram_filter.ps1` - Telegram filtering

### Core Libraries (15)
- `lib_coinex.ps1` - CoinEx API integration
- `lib_claude.ps1` - Claude/Anthropic LLM
- `lib_macro.ps1` - Macro indicators
- `lib_indicators.ps1` - Technical indicators
- `lib_seasonality.ps1` - Auto-pacing logic
- `lib_telegram.ps1` - Telegram notifications
- `lib_retry.ps1` - Retry logic
- `lib_idempotency.ps1` - Idempotency checks
- `lib_price_freshness.ps1` - Price staleness detection
- `lib_trailing.ps1` - Trailing stops
- `lib_trailing_adaptive.ps1` - Adaptive trailing
- `lib_trade_logger.ps1` - Trade logging
- `lib_validation_logger.ps1` - Validation logging
- `lib_observation_logger.ps1` - Observation logging
- `lib_supabase_integration.ps1` - Supabase integration (NEW)

### Agents (6)
- `triagem_agent.ps1` - Tier classification
- `mesa_agent.ps1` - Consensus voting
- `mentor_agent.ps1` - Final veto
- `gem_agent.ps1` - Gem detection
- `gem_executor.ps1` - Gem execution
- `knowledge_retriever.ps1` - Knowledge retrieval

### Orchestrators (2)
- `orchestrator_v6.ps1` - Main orchestrator (V6)
- `scanner.ps1` - Market scanner

### Support Libraries (10)
- `lib_esquadrao_mocks.ps1` - Mock fallbacks
- `lib_operational_whitelist.ps1` - Whitelist logic
- `lib_enhanced_short_entry.ps1` - SHORT entry filter
- `lib_mesa_consensus_relaxed.ps1` - Consensus relaxation
- `lib_quant_whitelist.ps1` - Quant whitelist
- `lib_top_candidates.ps1` - Top candidates selection
- `lib_fqs_drain.ps1` - FQS draining
- `lib_market_context.ps1` - Market context
- `lib_market_context_engine.ps1` - Market context engine
- `lib_live_guards.ps1` - Live guards

### Additional Support (8)
- `lib_promotion_gates.ps1` - Promotion gates
- `lib_orchestrator_parallel.ps1` - Parallel orchestration
- `lib_llm_quota_optimizer.ps1` - LLM quota management
- `lib_short_execution.ps1` - SHORT execution
- `lib_layer4_tori_timestop.ps1` - Layer 4 stops
- `lib_moon_bag.ps1` - Moon bag strategy
- `lib_position_register.ps1` - Position registration
- `lib_gem_safety.ps1` - Gem safety
- `lib_gem_auto_approve.ps1` - Gem auto-approval
- `lib_cycle_indicators.ps1` - Cycle indicators
- `lib_cycle_indicators_advanced.ps1` - Advanced cycle indicators
- `lib_mentor_hallucination_detector.ps1` - Hallucination detection
- `lib_fqs_enrichment_queue.ps1` - FQS enrichment
- `lib_tori_proximity.ps1` - TORI proximity
- `lib_mentor_reflection.ps1` - Mentor reflection
- `lib_universe_sweep.ps1` - Universe sweep
- `lib_hit_rate.ps1` - Hit rate tracking
- `lib_mentor_invariants.ps1` - Mentor invariants
- `lib_cost_tracker.ps1` - Cost tracking
- `lib_order_idempotency.ps1` - Order idempotency

**Total USED: ~50 files**

---

## ❌ UNUSED/GARBAGE FILES (Can Remove)

### Duplicate/Old Orchestrators (2)
- `orchestrator.ps1` - OLD VERSION (use orchestrator_v6.ps1 instead)
- `trailing_stop_manager.ps1` - OLD (use lib_trailing_adaptive.ps1)

### Unused Agents (3)
- `chain_agent.ps1` - Not loaded in scan_master.ps1
- `fund_agent.ps1` - Not loaded in scan_master.ps1
- `sent_agent.ps1` - Not loaded in scan_master.ps1
- `tech_agent_ai.ps1` - Not loaded in scan_master.ps1
- `position_sizer.ps1` - Not loaded in scan_master.ps1

### Unused Libraries (50+)
- `lib_alpha_vs_btc.ps1` - Unused
- `lib_alpha_wire.ps1` - Unused
- `lib_asymmetric_demote.ps1` - Unused
- `lib_atr_stop.ps1` - Unused
- `lib_auto_market_analysis.ps1` - Unused
- `lib_beta_cap_per_phase.ps1` - Unused
- `lib_capital_context.ps1` - Unused
- `lib_chart_patterns.ps1` - Unused
- `lib_cluster_filter.ps1` - Unused
- `lib_coinex_ai_integration.ps1` - Unused
- `lib_coinex_news.ps1` - Unused
- `lib_coinex_position_management.ps1` - Unused
- `lib_coinex_retry.ps1` - Unused
- `lib_cold_wallet_alert.ps1` - Unused
- `lib_cross_platform.ps1` - Unused
- `lib_csv_utils.ps1` - Unused
- `lib_cycle_context.ps1` - Unused
- `lib_cycle_indicators_v2.ps1` - Unused
- `lib_cycle_mocks.ps1` - Unused
- `lib_decision_reflection.ps1` - Unused
- `lib_dsr_global.ps1` - Unused
- `lib_entry_score_boost.ps1` - Unused
- `lib_executor_sizing.ps1` - Unused
- `lib_exit_ladder.ps1` - Unused
- `lib_feedback_loop.ps1` - Unused
- `lib_fqs_lazy_enrichment.ps1` - Unused
- `lib_fundamental_quality.ps1` - Unused
- `lib_gate_safety.ps1` - Unused
- `lib_halving_phase_context.ps1` - Unused
- `lib_http_error_monitoring.ps1` - Unused
- `lib_idea_triggers.ps1` - Unused
- `lib_journal.ps1` - Unused
- `lib_json_contract.ps1` - Unused
- `lib_kelly_adaptive.ps1` - Unused
- `lib_kelly_graduation.ps1` - Unused
- `lib_kelly_sizing.ps1` - Unused
- `lib_kelly_wire.ps1` - Unused
- `lib_ladder_tracker.ps1` - Unused
- `lib_living_whitelist.ps1` - Unused
- `lib_macro_audit.ps1` - Unused
- `lib_market_blacklist.ps1` - Unused
- `lib_market_router.ps1` - Unused
- `lib_market_router_v2.ps1` - Unused
- `lib_mentor_alpha_history.ps1` - Unused
- `lib_mentor_calibration.ps1` - Unused
- `lib_mentor_examples.ps1` - Unused
- `lib_mentor_gate_block.ps1` - Unused
- `lib_mentor_reflect.ps1` - Unused
- `lib_mentor_rules.ps1` - Unused
- `lib_mentor_schema.ps1` - Unused
- `lib_mentor_self_consistency.ps1` - Unused
- `lib_mentor_time_context.ps1` - Unused
- `lib_mesa_consensus.ps1` - Unused
- `lib_methodology_gate.ps1` - Unused
- `lib_multi_tp_ladder.ps1` - Unused
- `lib_news_entry_boost.ps1` - Unused
- `lib_order_routed.ps1` - Unused
- `lib_order_validation.ps1` - Unused
- `lib_override_expiration.ps1` - Unused
- `lib_performance_analytics.ps1` - Unused
- `lib_position_protection.ps1` - Unused
- `lib_position_risk_monitor.ps1` - Unused
- `lib_promotion_cycle.ps1` - Unused
- `lib_promotion_ladder.ps1` - Unused
- `lib_promotion_paper.ps1` - Unused
- `lib_promotion_telegram.ps1` - Unused
- `lib_pump_buy_gate.ps1` - Unused
- `lib_rate_limiter.ps1` - Unused
- `lib_runspace_audit.ps1` - Unused
- `lib_runspace_warning.ps1` - Unused
- `lib_schema_validation.ps1` - Unused
- `lib_short_signals.ps1` - Unused
- `lib_signal_generator.ps1` - Unused
- `lib_staleness_engine.ps1` - Unused
- `lib_state_store.ps1` - Unused (but might be needed for Supabase)
- `lib_supabase_management.ps1` - Unused
- `lib_telegram_v2.ps1` - Unused (use lib_telegram.ps1)
- `lib_trailing_exhaust.ps1` - Unused
- `lib_trailing_macro.ps1` - Unused
- `lib_trailing_micro.ps1` - Unused
- `lib_trailing_orphan.ps1` - Unused
- `lib_trailing_smart.ps1` - Unused
- `lib_trailing_stop_intelligent.ps1` - Unused
- `lib_trailing_stop_manager.ps1` - Unused
- `lib_trendline_filter.ps1` - Unused
- `lib_validation_log.ps1` - Unused
- `lib_veto_feedback.ps1` - Unused
- `lib_vol_climax_optimization.ps1` - Unused
- `lib_watchdog_backoff.ps1` - Unused
- `lib_whale_detection.ps1` - Unused
- `lib_whale_watcher.ps1` - Unused
- `lib_wss_forward_trading.ps1` - Unused
- `lib_wyckoff_spring.ps1` - Unused

### Other Files (5)
- `constants_loader.ps1` - Loaded but might be redundant
- `journal.ps1` - Unused
- `DEPLOYMENT_TDD_2026_05_23.ps1` - Old deployment file

**Total UNUSED: ~107 files (68%)**

---

## 🎯 Recommendation

### KEEP (50 files)
All files listed in "ACTIVELY USED FILES" section

### REMOVE (107 files)
All files listed in "UNUSED/GARBAGE FILES" section

### VERIFY BEFORE REMOVING
- `lib_state_store.ps1` - Check if needed for Supabase integration
- `constants_loader.ps1` - Check if actually used

---

## 📊 Impact of Cleanup

**Before:**
- 157 files
- Confusing to navigate
- Hard to identify what's actually used
- Maintenance nightmare

**After:**
- ~50 files
- Clear structure
- Easy to understand
- Maintainable

**Reduction:** 68% fewer files

---

## 🚀 Cleanup Plan

1. **Backup** - Create backup of agents folder
2. **Identify** - Verify which files are actually used
3. **Remove** - Delete unused files
4. **Test** - Run system to verify nothing breaks
5. **Commit** - Clean commit with removed files

---

## ⚠️ Important Notes

- Do NOT remove files without verifying they're not used
- Some files might be loaded dynamically (check for string-based imports)
- Test thoroughly after cleanup
- Keep git history (files can be recovered if needed)

---

**Status:** Ready for cleanup  
**Estimated Time:** 30 minutes  
**Risk Level:** LOW (can be reverted via git)
