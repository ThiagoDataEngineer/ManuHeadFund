# 🚀 ManuHeadFund - CoinEx AI Trading System

Sistema automatizado de trading com IA (Mentor Agent) + Auto-Trade Engine para CoinEx SPOT + FUTURES (HYBRID 50/50).  
**Status**: ✅ **READY FOR LIVE SPOT $2.70** (FASE 1) | **Last Updated**: 2026-06-09

---

## 🎯 VALIDACAO BRUTAL — vol_climax Signal (2026-06-09) ⭐

**TDD Phase 1 COMPLETE**: Backtest 7.4 anos validou 3 sinais.

| Signal | Sharpe | Trades | Win% | Status |
|--------|--------|--------|------|--------|
| **vol_climax** | **8.81** | 65 | 55.4% | ✅ **ELITE — ACTIVATE NOW** |
| tori | 6.34 | 1,236 | 50.4% | ✅ Complementary |
| faro_v3 | 4.49 | 6 | 50% | ⚠️ Paused (small sample) |

**Action**: Phase 2 (wire in gem_agent) happening NOW.
**Target**: 5-10 vol_climax trades in 24h with 45%+ win rate.
**Docs**: Read [VALIDACAO_BRUTAL_INDEX](./journal/VALIDACAO_BRUTAL_INDEX_2026_06_09.md) then [ACAO_IMEDIATA](./journal/ACAO_IMEDIATA_2026_06_09.md)

---

## 🎯 Quick Start

```bash
# LOCAL EXECUTION (manual - development)
.\scripts\scan_master.ps1

# CI/CD EXECUTION (automatic - production)
# Runs via GitHub Actions every 15 minutes
```

---

## 📋 Índice

- **[Execution Modes](#-execution-modes)** — Local vs GitHub Actions
- **[System Architecture](#-system-architecture)** — Como funciona
- **[Data Layer](#-data-layer)** — Supabase integration
- **[Development](#-development)** — Setup local
- **[Deployment](#-deployment)** — GitHub Actions
- **[Troubleshooting](#-troubleshooting)** — Problemas comuns

---

## 🔄 Execution Modes

### LOCAL (Development/Manual)
Run manually on your machine for testing:

```powershell
# Single cycle
.\scripts\scan_master.ps1 -Once

# Continuous loop (15min intervals)
.\scripts\scan_master.ps1

# With specific pairs
.\scripts\scan_master.ps1 -Pairs BTCUSDT,ETHUSDT -Once
```

**Use when:**
- Testing new features
- Debugging issues
- Manual override needed

---

### GITHUB ACTIONS (Production/Automatic)
Runs automatically every 15 minutes via CI/CD:

**Workflow**: `.github/workflows/trading-pipeline.yml`

```yaml
# Executes every 15 minutes
schedule:
  - cron: '*/15 * * * *'
```

**What it does:**
1. ✅ Connects to Supabase (centralized data)
2. ✅ Runs GemScan (market analysis)
3. ✅ Runs Orchestrator V6 (mentor debate)
4. ✅ Executes trades (if approved)
5. ✅ Updates dashboard
6. ✅ Logs everything

**Advantages:**
- ✅ Runs 24/7 without manual intervention
- ✅ Scalable to production
- ✅ Full audit trail
- ✅ No local machine needed

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   EXECUTION TRIGGERS                        │
│  Local (manual)  OR  GitHub Actions (automatic every 15m)  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                    scan_master.ps1                          │
│  (Main orchestrator loop)                                   │
├─────────────────────────────────────────────────────────────┤
│  1. GemScan          - Detect low-cap opportunities         │
│  2. Orchestrator V6  - Triagem → Mesa → Mentor Debate       │
│  3. TrailingStops    - Adaptive exits                        │
│  4. Dashboard        - Visual monitoring                     │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌───────────────┐ ┌───────────────┐ ┌──────────────┐
│  Triagem      │ │   Mesa        │ │ Mentor       │
│  (Tier A-D)   │ │ (Consensus)   │ │ (Debate)     │
│  ✓ Simple     │ │ ✓ Vote 3x     │ │ ✓ Final veto │
│  ✓ Fast       │ │ ✓ Strong consensus │         │
└───────────────┘ └───────────────┘ └──────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         ↓
        ┌────────────────────────────────┐
        │  TRADE EXECUTION / SKIP        │
        │  ✓ EXECUTAR (approved)         │
        │  ✓ OBSERVAR (paper trade)      │
        │  ✓ SKIP (rejected)             │
        └────────────────────────────────┘
                         │
                         ↓
        ┌────────────────────────────────┐
        │  Supabase → Real-time sync     │
        │  ✓ FQS Registry                │
        │  ✓ TORI Proximity              │
        │  ✓ Alpha/Beta History          │
        │  ✓ Drawdown Tracking           │
        │  ✓ Regime State                │
        └────────────────────────────────┘
```

---

## 💾 Data Layer (Supabase)

### Schema (7 Tables)
```
manuheadfund
├── fqs_registry          - Trade candidates queue
├── tori_proximity        - TORI proximity tracking
├── alpha_history         - Alpha accumulation
├── beta_history          - Beta cycle history
├── drawdown_history      - Drawdown events
├── regime_state          - Current market regime
└── dsr_global            - Global DSR state
```

### Key Features
- ✅ Real-time sync (no manual updates)
- ✅ 155+ records migrated
- ✅ Automatic backup
- ✅ Graceful fallback to local JSON

### Access
```powershell
# Check Supabase status
$config = . .\agents\config.local.ps1
# SUPABASE_URL and SUPABASE_SERVICE_KEY loaded from config.local.ps1
```

---

## 🛠️ Development

### Prerequisites
- PowerShell 7+ (or 5 with .NET Framework)
- CoinEx API key (in `agents/config.local.ps1`)
- Supabase URL and API key (optional, falls back to JSON)

### Local Setup
```powershell
# 1. Configure credentials
# Edit agents/config.local.ps1 with:
# - COINEX_API_KEY
# - COINEX_API_SECRET
# - SUPABASE_URL (optional)
# - SUPABASE_SERVICE_KEY (optional)

# 2. Run single cycle
.\scripts\scan_master.ps1 -Once

# 3. Check logs
Get-Content logs/master_*.log -Tail 50
```

### Testing
```powershell
# Run Pester tests
Invoke-Pester tests/ -Output Detailed

# Current status: 41/41 tests passing ✅
```

### File Organization
```
agents/             - Core trading logic (79 files - all active)
├── config*.ps1     - Configuration
├── *_agent.ps1     - Main agents (Triagem, Mesa, Mentor)
├── lib_*.ps1       - Libraries (indicators, exchanges, etc)
└── orchestrator_v6.ps1 - Main orchestrator

scripts/            - Utilities
├── scan_master.ps1 - Main loop
├── scanner.ps1     - Market scanner
└── *.ps1           - Other tools

tests/              - Pester tests (41 tests)
├── supabase_*.Tests.ps1
└── *.Tests.ps1

docs/               - Documentation (archived - see DEPLOYMENT_COMPLETE_2026_06_01.md)
```

---

## 🚀 Deployment

### GitHub Actions Workflow

**File**: `.github/workflows/trading-pipeline.yml`

```yaml
name: Trading Pipeline

on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes
  workflow_dispatch:         # Manual trigger

jobs:
  trade:
    runs-on: windows-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v3
      
      - name: Run Trading Cycle
        run: |
          .\scripts\scan_master.ps1
      
      - name: Upload Logs
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: trading-logs
          path: logs/
```

### Environment Variables (GitHub Secrets)
```
COINEX_API_KEY         - Your CoinEx API key
COINEX_API_SECRET      - Your CoinEx API secret
SUPABASE_URL           - Supabase project URL
SUPABASE_SERVICE_KEY   - Supabase service key
```

**Set via**: Settings → Secrets and Variables → Actions

### Deployment Steps
1. Push code to main branch
2. GitHub Actions automatically triggers every 15 minutes
3. Check workflow status in Actions tab
4. View logs in artifacts

---

## 📊 Monitoring

### Local Logs
```powershell
# View latest logs
Get-Content logs/master_*.log -Tail 50

# Watch live
Get-Content logs/master_*.log -Tail 20 -Wait

# Check specific date
Get-Content "logs/master_2026-06-01.log" -Tail 100
```

### Check Data Gates
```powershell
# All data gates satisfied?
# Look for logs with "FQS", "TORI", "ALPHA", "BETA", "DRAWDOWN"
# Should all show as READY/SATISFIED
```

### Dashboard
```
Open: dashboard/index.html
Auto-refreshes every 5 minutes
Shows: Positions, PNL, Capital, Alerts
```

---

## ✅ System Status

### Current State (2026-06-08)
| Component | Status | Notes |
|-----------|--------|-------|
| Signal Detection | ✅ LIVE | Vol_Climax + Engulfing COMBO (62.6% WR) |
| Hybrid Allocation | ✅ LIVE | SPOT 50% + FUTURES 50% (67.5% combined WR) |
| Capital (ONCHAIN) | ✅ LIVE | Fetches SPOT+FUTURES real-time from CoinEx API |
| PlaceOrder | ✅ READY | 22/22 tests (idempotency, retry, fill validation) |
| Exit Logic | ✅ READY | 29/29 tests (TP +2%, SL -1%, trailing, time-based) |
| Rebalancing | ✅ READY | 13/13 tests (daily 17:00 BRT, >10% drift trigger) |
| Telegram | ✅ READY | 5 commands (/status /halt /resume /close /scan /summary) |
| Paper Mode | ✅ READY | Full simulation (60% TP, 40% SL, journal logging) |
| Tests | ✅ PASS | 64+ tests passing (100%) |
| Trading | ✅ READY | Ready for LIVE SPOT $2.70 (FASE 1) |

### Performance
- **Functions Available**: 4/4 ✅
- **Data Sync**: Real-time (Supabase) ✅
- **Execution Cycle**: Every 15 minutes ✅
- **Success Rate**: 100% (last cycle) ✅

---

## 🆘 Troubleshooting

### Issue: "Function not found"
**Solution**: Check `agents/orchestrator_v6.ps1` loads all dependencies
```powershell
# Verify dependencies loaded
. agents/orchestrator_v6.ps1
# Should load without errors
```

### Issue: "Data gates not satisfied"
**Solution**: Check Supabase connection or fallback to local JSON
```powershell
# Check Supabase status
$config = . agents/config.local.ps1
# SUPABASE_URL should be set
```

### Issue: "GitHub Actions workflow failed"
**Check**: 
1. Secrets configured in GitHub Settings
2. Workflow syntax valid (`.github/workflows/trading-pipeline.yml`)
3. PowerShell script runs locally first

### Issue: "No trades executing"
**Check**:
1. Mentor agent approved (check logs for EXECUTAR)
2. Data gates satisfied (FQS, TORI, ALPHA, BETA, DRAWDOWN)
3. Market conditions met
4. Capital available

---

## 🔧 Common Commands

```powershell
# LOCAL DEVELOPMENT

# Run single cycle
.\scripts\scan_master.ps1 -Once

# Run with specific pairs
.\scripts\scan_master.ps1 -Pairs BTCUSDT,ETHUSDT -Once

# Continuous loop
.\scripts\scan_master.ps1

# Run tests
Invoke-Pester tests/ -Output Detailed

# Check logs
Get-Content logs/master_*.log -Tail 50 -Wait

# GITHUB ACTIONS (automatic)

# Trigger manually
# Go to: Actions → Trading Pipeline → Run workflow

# View results
# Check: Actions tab → Latest run → Logs
```

---

## 📂 Project Structure

```
Coinex_AI_USER_API/
├── README.md                           ← You are here
├── CLAUDE.md                           ← Claude context
├── DEPLOYMENT_COMPLETE_2026_06_01.md   ← Current status
│
├── agents/                             (79 active files)
│   ├── config.ps1                      ← Configuration
│   ├── config.local.ps1                ← Secrets (API keys)
│   ├── orchestrator_v6.ps1             ← Main orchestrator
│   ├── *_agent.ps1                     ← Trading agents
│   └── lib_*.ps1                       ← Libraries
│
├── scripts/
│   ├── scan_master.ps1                 ← Main entry point
│   ├── scanner.ps1                     ← Market scanner
│   └── *.ps1                           ← Utilities
│
├── tests/
│   └── *.Tests.ps1                     ← Pester tests (41 total)
│
├── .github/
│   └── workflows/
│       └── trading-pipeline.yml        ← GitHub Actions CI/CD
│
├── backtest/                           ← Backtesting (Python)
├── dashboard/                          ← HTML dashboard
├── logs/                               ← Trading logs
├── journal/                            ← Execution data
└── config/                             ← Configuration files
```

---

## 🎓 Key Concepts

### Orchestrator V6 Architecture
```
Triagem (Tier A-D)
    ↓
Whitelist (Wave 2)
    ↓
Mesa (Consensus)
    ↓
Mentor Debate (Final Veto)
    ↓
Trade Execution or Skip
```

### Data Flow
```
CoinEx API
    ↓
GemScan (opportunities)
    ↓
Orchestrator (validation)
    ↓
Mentor (approval)
    ↓
Supabase (real-time sync)
    ↓
Trade Execution
```

---

## 📚 Documentation

- **DEPLOYMENT_COMPLETE_2026_06_01.md** — Current system status
- **CLAUDE.md** — AI context for development

Archived docs in Git history (see commits).

---

## 🚀 Deployment Checklist

For production deployment:

- [ ] All secrets configured in GitHub (COINEX_API_KEY, etc)
- [ ] Supabase credentials valid
- [ ] GitHub Actions workflow enabled
- [ ] Test run successful
- [ ] Logs reviewed for errors
- [ ] First trade verified
- [ ] Monitoring setup

---

## 📞 Quick Reference

| Need | Command | File |
|------|---------|------|
| Run locally | `.\scripts\scan_master.ps1 -Once` | N/A |
| Run continuous | `.\scripts\scan_master.ps1` | N/A |
| Run tests | `Invoke-Pester tests/` | tests/ |
| Check logs | `Get-Content logs/master_*.log -Tail 50` | logs/ |
| View config | Edit `agents/config.local.ps1` | agents/ |
| GitHub Actions | View `.github/workflows/trading-pipeline.yml` | .github/ |
| Dashboard | Open `dashboard/index.html` | dashboard/ |

---

## 📊 Recent Changes (2026-06-08)

✅ **5 CRITICAL BLOCKERS IMPLEMENTED**
1. **PlaceOrder** (lib_place_order.ps1) — Idempotent BUY/SELL execution with retry + fill validation (22/22 tests)
2. **Exit Logic** (lib_exit_logic.ps1) — Multi-exit: TP (+2%), SL (-1%), Trailing Stop, Time-based (60min) (29/29 tests)
3. **Rebalancing Daemon** (lib_rebalancing_daemon.ps1) — Daily 17:00 BRT SPOT/FUTURES 50/50 maintenance, >10% drift trigger (13/13 tests)
4. **Telegram Commands** (lib_telegram_commands.ps1) — /status /halt /resume /close /scan /summary + auto-alerts
5. **Paper Mode** (lib_paper_mode.ps1) — Full simulation before LIVE (60% TP / 40% SL outcomes, journal logging)

✅ **CAPITAL ONCHAIN INTEGRATION**
- lib_hybrid_orchestrator.ps1: Initialize-HybridConfig() fetches SPOT+FUTURES real-time
- lib_auto_trade_engine.ps1: Get-CurrentCapitalOnchain() with fallback
- All hardcoded capital values removed (2700.85 → dynamic fetch)

✅ **ARCHITECTURE**
- Vol_Climax + Engulfing COMBO: 62.6% WR across all 4 regimes
- HYBRID 50/50 SPOT/FUTURES: 67.5% combined WR vs 63% SPOT-only
- Regime-aware position sizing with hard cap enforcement (1% per trade)

**System Status**: ✅ **READY FOR LIVE SPOT $2.70 (FASE 1)**

---

**Last Updated**: June 8, 2026 / 2:30pm BRT  
**Status**: ✅ ALL BLOCKERS COMPLETE  
**Ready for Trading**: YES — switch Set-TradingMode -Mode LIVE  
**Capital**: $2,700.85 (SPOT $1,350.43 + FUTURES $1,350.42)
