# 🚀 ManuHeadFund - CoinEx AI Trading System

Sistema automatizado de trading com IA (Mentor Agent) para CoinEx Futures.  
**Status**: ✅ PRODUCTION READY | **Last Updated**: 2026-06-01

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

### Current State (2026-06-01)
| Component | Status | Notes |
|-----------|--------|-------|
| Supabase Integration | ✅ LIVE | 7 tables, 155+ records |
| Functions | ✅ FIXED | All 4 missing functions loaded |
| Tests | ✅ PASS | 41/41 tests passing (100%) |
| Repository | ✅ CLEAN | 79 files in /agents (49.7% reduction) |
| Trading | ✅ READY | All data gates satisfied |
| Documentation | ✅ UPDATED | Consolidated (4 files only) |

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

## 📊 Recent Changes (2026-06-01)

✅ **COMPLETE CLEANUP & DEPLOYMENT**
- Fixed 4 missing functions
- Deployed Supabase integration (7 tables, 155+ records)
- Removed 78 unused files from /agents (49.7% reduction)
- Removed 30 redundant docs from root
- All 41 tests passing

**System Status**: ✅ PRODUCTION READY

---

**Last Updated**: June 1, 2026  
**Status**: ✅ LIVE AND READY  
**Ready for Trading**: YES
