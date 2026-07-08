# Tori Daemon 24/7 Scanner — Quick Start

Production-grade 24/7 daemon scanner for analyzing 100+ CoinEx futures pairs using Tori Trades trendline confluence methodology.

## Quick Start (30 seconds)

```powershell
cd agents

# 1. Verify config
cat config.local.ps1  # Should have COINEX_ACCESS_ID + COINEX_SECRET_KEY

# 2. Start daemon
.\Start-ToriDaemon.ps1

# 3. Check status
Get-Job -Name "ToriDaemon*"

# 4. View logs
Get-Content ../journal/tori_daemon.log -Tail 20
```

## What It Does

Every 4 hours:

1. **Scans 150 USDT pairs** across 1W, 1D, 4H, 1H timeframes
2. **Detects trendlines** with ≥2 touches + slope validation
3. **Calculates confluence** (Volume Climax, RSI Extreme, Fractal, CHoCH, Volume Profile)
4. **Filters by score** (≥80/100 threshold)
5. **Tracks setups** with entry, stop, target prices
6. **Monitors P&L** and marks closed when targets hit or stops triggered
7. **Sends Telegram alerts** for new setups, target hits, daily summary
8. **Saves state** to JSON for persistence & recovery

## Files

| File | Purpose |
|------|---------|
| `tori_daemon_24h.ps1` | Main daemon loop (scan, analyze, track) |
| `tori_telegram_alerts.ps1` | Alert formatting & Telegram delivery |
| `tori_daemon_reporter.ps1` | HTML dashboard + JSON/CSV export |
| `Start-ToriDaemon.ps1` | Launcher (validates config, starts jobs) |
| `Stop-ToriDaemon.ps1` | Graceful shutdown + cleanup |
| `tori_daemon_watchdog.ps1` | Process monitor (auto-restart on crash) |
| `../docs/TORI_DAEMON_DEPLOYMENT.md` | Full deployment guide |

## State & Monitoring

**Files created:**
- `journal/tori_daemon_state.json` — Active setups + closed trades + metrics
- `journal/tori_daemon.log` — Daemon logs
- `journal/tori_daemon_heartbeat.txt` — 5min heartbeat for watchdog
- `journal/tori_daemon_watchdog.log` — Watchdog logs
- `journal/reports/tori_dashboard.html` — Interactive dashboard

## Key Commands

```powershell
# Check status
Get-Job -Name "ToriDaemon*"

# View current state
(Get-Content journal/tori_daemon_state.json | ConvertFrom-Json).active_setups | 
  Select pair, timeframe, trend_type, confidence_score, entry_price, unrealized_pnl

# View logs (last 50 lines)
Get-Content journal/tori_daemon.log -Tail 50

# Generate HTML dashboard
. tori_daemon_reporter.ps1; Export-ToriReports
# Open: ../journal/reports/tori_dashboard.html

# Stop daemon gracefully
.\Stop-ToriDaemon.ps1

# Force kill (if hung)
.\Stop-ToriDaemon.ps1 -Force
```

## Configuration

Edit `config.local.ps1`:

```powershell
# REQUIRED: CoinEx API
$env:COINEX_ACCESS_ID = "your_access_id"
$env:COINEX_SECRET_KEY = "your_secret_key"

# OPTIONAL: Telegram alerts
$env:TELEGRAM_BOT_TOKEN = "your_bot_token"
$env:TELEGRAM_CHAT_ID = "your_chat_id"
```

Then adjust in `tori_daemon_24h.ps1` if needed:

```powershell
$script:SCAN_INTERVAL_MINUTES = 240    # 4-hour cycle
$script:CONFLUENCE_THRESHOLD = 80      # Min score
$script:MAX_PAIRS_PER_SCAN = 150       # Pairs per scan
```

## Telegram Alerts

Three alert types:

### 1. New Setup (Confluence ≥ 80)

```
🟢 NEW SETUP — BTCUSDT [1D]
⭐ Confidence: 87/100
📍 Entry: 63,420.50
🛑 Stop: 64,650.30
🎯 Target: 60,500.00
💰 R:R: 3.3x
Signals: Volume Climax, RSI Extreme, Fractal
```

### 2. Target Hit

```
✅ CLOSED — TARGET HIT
🟢 BTCUSDT [1D]
Entry: 63,420.50
Exit: 60,500.00
Profit: +$2,920.50 (+4.6%)
Hold: 3h 24m
```

### 3. Stop Hit

```
❌ CLOSED — STOPPED
🟢 BTCUSDT [1D]
Entry: 63,420.50
Stop Hit: 64,650.30
Loss: -$1,229.80 (-1.9%)
Hold: 47m
```

## Dashboard Example

Open `journal/reports/tori_dashboard.html` after running:

```powershell
. tori_daemon_reporter.ps1
Export-ToriReports
Start-Process journal/reports/tori_dashboard.html
```

Shows:
- Active setups table (pair, TF, type, score, entry, P&L)
- Closed trades history (entry, exit, profit/loss)
- Performance stats (win rate, avg confluence, total P&L)
- Signal performance breakdown

## Troubleshooting

### Daemon won't start

```powershell
# Check config
Test-Path config.local.ps1

# Check libs
ls lib_tori*.ps1 lib_coinex.ps1

# View startup log
Get-Content ../journal/tori_daemon_startup.log -Tail 30
```

### Daemon crashes frequently

```powershell
# Check watchdog logs
Get-Content ../journal/tori_daemon_watchdog.log -Tail 50

# Check restart history
Get-Content ../journal/tori_daemon_restarts.json | ConvertFrom-Json
```

### No Telegram alerts

```powershell
# Verify tokens
$env:TELEGRAM_BOT_TOKEN
$env:TELEGRAM_CHAT_ID

# Test manually
. tori_telegram_alerts.ps1
Send-TelegramMessage -Message "Test"
```

### Memory/disk growing

```powershell
# Check state file size
(Get-Item ../journal/tori_daemon_state.json).Length / 1MB

# If large (>50MB), restart daemon to reset state
.\Stop-ToriDaemon.ps1
.\Start-ToriDaemon.ps1
```

## Performance Targets

- **Scan time:** 8-10 minutes per 150 pairs
- **Memory:** <200MB
- **CPU:** <5% idle, <50% during scan
- **Disk write:** <100KB per cycle
- **API calls:** 50 req/min (CoinEx limit)

## Architecture

```
Main Loop (4-hour cycle)
├─ Update pair cache (6h refresh)
├─ Fetch candles (150 pairs × 4 TF = 600 calls)
├─ Detect trendlines (LONG/SHORT)
├─ Calculate confluence (0-100 score)
├─ Filter threshold (≥80)
├─ Update existing setups (check target/stop)
├─ Save state (JSON)
├─ Send Telegram alerts
└─ Sleep 4 hours + 5min heartbeat
```

## Monitoring

Check health anytime:

```powershell
# Is daemon running?
$job = Get-Job -Name "ToriDaemon*" -ErrorAction SilentlyContinue
$job.State  # Running, Stopped, Failed, etc.

# How old is heartbeat? (should be <300sec)
$hb = Get-Content journal/tori_daemon_heartbeat.txt | ConvertFrom-Json
(Get-Date) - [DateTime]::Parse($hb.timestamp)

# How many setups active?
(Get-Content journal/tori_daemon_state.json | ConvertFrom-Json).active_setups.Count
```

## What's NOT Included

This daemon **does NOT:**
- Execute real trades (analysis only)
- Replace manual trading decisions
- Guarantee profitability
- Use leverage (paper P&L only)

Use as **analysis tool + alert system**, not automated trader.

## Full Deployment Guide

See `../docs/TORI_DAEMON_DEPLOYMENT.md` for:
- Installation from scratch
- Automated Windows/Linux startup
- Advanced configuration
- Performance tuning
- Disaster recovery
- Monitoring integration (Prometheus, etc.)

---

**Version:** 1.0 | **Status:** Production Ready | **PS 5.1+** | **No external dependencies**
