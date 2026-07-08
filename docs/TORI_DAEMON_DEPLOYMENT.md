# Tori Daemon 24/7 Scanner — Deployment Guide

**Version:** 1.0  
**Status:** Production Ready  
**Compatibility:** PowerShell 5.1+  
**Platform:** Windows, Linux (WSL), macOS  

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Deployment](#deployment)
6. [Operations](#operations)
7. [Troubleshooting](#troubleshooting)
8. [Performance Tuning](#performance-tuning)
9. [Monitoring](#monitoring)
10. [Disaster Recovery](#disaster-recovery)

---

## Overview

**Tori Daemon** is a production-grade 24/7 scanner that continuously analyzes 100+ CoinEx futures pairs across multiple timeframes using the Tori Trades trendline confluence methodology.

### Key Features

- **Continuous 4-hour scan cycles** across 150 USDT pairs
- **Trendline confluence detection** with 5 signal types (Volume Climax, RSI Extreme, Fractal, CHoCH, Volume Profile)
- **State persistence** with crash recovery
- **Automatic watchdog monitoring** with process auto-restart
- **Telegram alerts** for new setups, target hits, and stops
- **HTML dashboard** with performance analytics
- **JSON/CSV export** for external analysis

### System Components

| Component | Purpose | File |
|-----------|---------|------|
| Core Daemon | Main scanning loop | `tori_daemon_24h.ps1` |
| Telegram Alerts | Alert formatting & delivery | `tori_telegram_alerts.ps1` |
| HTML Reporter | Dashboard generation | `tori_daemon_reporter.ps1` |
| Launcher | Startup orchestration | `Start-ToriDaemon.ps1` |
| Shutdown | Graceful cleanup | `Stop-ToriDaemon.ps1` |
| Watchdog | Process health monitoring | `tori_daemon_watchdog.ps1` |

---

## Architecture

### Scanning Pipeline

```
┌─────────────────────────────────────────────────────────┐
│          Tori Daemon (4-hour cycle)                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. Update Pair Cache (6-hour refresh)                │
│     └─ Load 100+ USDT pairs from CoinEx               │
│                                                         │
│  2. Batch Analysis (150 pairs, 4 timeframes)          │
│     ├─ Fetch 300 candles per pair/timeframe            │
│     ├─ Detect trendlines (LONG/SHORT)                 │
│     ├─ Calculate confluence score (0-100)             │
│     └─ Filter by threshold (≥80)                       │
│                                                         │
│  3. State Update                                        │
│     ├─ Check existing setups for target/stop hits      │
│     ├─ Calculate unrealized P&L                        │
│     ├─ Archive closed trades                           │
│     └─ Save state to JSON                              │
│                                                         │
│  4. Alert Dispatch                                      │
│     ├─ Telegram: New setups, targets, stops            │
│     ├─ Daily reports                                   │
│     └─ HTML dashboard generation                       │
│                                                         │
│  5. Sleep 4 hours                                       │
│     └─ Heartbeat every 5 minutes                        │
│                                                         │
└─────────────────────────────────────────────────────────┘
         │
         ├──> journal/tori_daemon_state.json (state)
         ├──> journal/tori_daemon.log (logs)
         ├──> journal/tori_daemon_heartbeat.txt (monitoring)
         └──> journal/reports/tori_dashboard.html (dashboard)
```

### Rate Limiting Strategy

- **API calls:** 50 req/min public (CoinEx limit)
- **Per scan:** 150 pairs × 4 timeframes = 600 candle calls
- **Throttle:** 100ms between calls = 6 min for full scan
- **Buffer:** 4-hour cycle allows 30+ minute overhead

### State Persistence

State file: `journal/tori_daemon_state.json`

```json
{
  "timestamp": "2026-07-08T15:30:00Z",
  "last_scan_time": "2026-07-08T15:25:00Z",
  "active_setups": [
    {
      "id": "BTCUSDT_1D_SHORT_202607081530",
      "pair": "BTCUSDT",
      "timeframe": "1D",
      "trend_type": "SHORT",
      "confidence_score": 87,
      "entry_price": 63420.50,
      "stop_loss": 64650.30,
      "target_price": 60500.00,
      "unrealized_pnl": -850.50,
      "status": "OPEN"
    }
  ],
  "closed_trades": [ ... ],
  "performance": {
    "total_scans": 45,
    "pairs_analyzed": 150,
    "setups_found": 12,
    "avg_confluence_score": 84.2,
    "win_rate": 0.72,
    "total_pnl": 3250.75
  }
}
```

### Watchdog Flow

```
Watchdog (30s cycle)
  ├─ Check heartbeat file age
  │   └─ If > 10 min: DAEMON DEAD
  │       └─ Attempt restart (max 3 times)
  │
  ├─ Check process running
  │   └─ If process missing + recent heartbeat: CRASH
  │       └─ Restart daemon
  │
  └─ Update lock file
      └─ For external monitoring
```

---

## Installation

### Prerequisites

- **PowerShell 5.1+** (Windows built-in, install on Linux/macOS)
- **CoinEx API credentials** (Access ID + Secret Key)
- **Telegram bot token + chat ID** (optional, for alerts)
- **Network:** 24/7 internet connection

### Step 1: Verify Dependencies

```powershell
# Check PowerShell version
$PSVersionTable.PSVersion

# Expected: 5.1.xxxxx or higher
# Windows 10+: Already installed
# Linux: sudo apt install powershell (Debian) or brew install powershell (macOS)
```

### Step 2: Verify Required Libraries

```powershell
cd agents

# Check that these files exist:
# - lib_tori_confluence_detector.ps1
# - lib_tori_trades_scanner.ps1
# - lib_coinex.ps1
# - lib_rate_limiter.ps1

ls lib_tori*.ps1 lib_coinex.ps1
```

### Step 3: Create Config File

```powershell
# Create agents/config.local.ps1
# DO NOT commit to Git!

$env:COINEX_ACCESS_ID = "your_access_id"
$env:COINEX_SECRET_KEY = "your_secret_key"

# Optional: Telegram alerts
$env:TELEGRAM_BOT_TOKEN = "your_bot_token"
$env:TELEGRAM_CHAT_ID = "your_chat_id"
```

### Step 4: Create Journal Directory

```powershell
mkdir journal/reports -Force
```

---

## Configuration

### Daemon Parameters (tori_daemon_24h.ps1)

Key variables at top of file:

```powershell
$script:SCAN_INTERVAL_MINUTES = 240           # 4 hours
$script:HEARTBEAT_INTERVAL_SEC = 300          # 5 minutes
$script:CANDLES_LIMIT = 300                   # Historical candles
$script:TIMEFRAMES = @("1W", "1D", "4H", "1H")  # Scan timeframes
$script:CONFLUENCE_THRESHOLD = 80             # Min score
$script:MIN_AMOUNT_USDT = 50                  # Min order size
$script:PAIR_CACHE_HOURS = 6                  # Cache refresh
$script:MAX_PAIRS_PER_SCAN = 150              # Pairs per cycle
$script:API_RATE_LIMIT_DELAY_MS = 100        # Throttle
```

### Watchdog Parameters (tori_daemon_watchdog.ps1)

```powershell
$script:HEARTBEAT_TIMEOUT_SEC = 600           # 10 min = dead
$script:CHECK_INTERVAL_SEC = 30               # Monitor cycle
$script:MAX_RESTART_ATTEMPTS = 3              # Max restarts
```

### Alert Configuration (tori_telegram_alerts.ps1)

```powershell
$script:MIN_SCORE_ALERT = 80         # Alert when >= 80
$script:MIN_RR_ALERT = 2.5           # Alert when >= 2.5x
```

---

## Deployment

### Quick Start

```powershell
cd agents
.\Start-ToriDaemon.ps1
```

**Expected output:**

```
╔════════════════════════════════════════════════════════════╗
║  Starting Tori Daemon - 24/7 Trendline Scanner           ║
╚════════════════════════════════════════════════════════════╝

[2026-07-08 15:30:00] [INFO] Verifying prerequisites...
[2026-07-08 15:30:01] [SUCCESS] PowerShell version OK: 5.1.19041.4106
[2026-07-08 15:30:01] [SUCCESS] Config file found
[2026-07-08 15:30:02] [SUCCESS] Daemon launched as job: ToriDaemon_20260708_153002 (ID: 8)
[2026-07-08 15:30:07] [SUCCESS] Daemon process confirmed running
[2026-07-08 15:30:07] [SUCCESS] Watchdog started (ID: 9)

╔════════════════════════════════════════════════════════════╗
║         Tori Daemon Startup Complete                      ║
╚════════════════════════════════════════════════════════════╝

📊 Daemon Information:
  Job Name: ToriDaemon_20260708_153002
  Job ID: 8
  Status: Running
  Started: 2026-07-08 15:30:02

📍 Locations:
  Daemon Log: C:\...\journal\tori_daemon.log
  Startup Log: C:\...\journal\tori_daemon_startup.log
  State File: C:\...\journal\tori_daemon_state.json
  Dashboard: C:\...\journal\reports\tori_dashboard.html

🎯 Quick Commands:
  Check daemon: Get-Job -Name 'ToriDaemon*'
  View log: Get-Content journal/tori_daemon.log -Tail 50
  Stop daemon: .\Stop-ToriDaemon.ps1
```

### Automated Startup (Windows)

Create scheduled task for auto-start:

```powershell
# Run as Administrator
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"C:\path\to\agents\Start-ToriDaemon.ps1`""

$taskTrigger = New-ScheduledTaskTrigger -AtStartup

$taskSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable `
  -Compatibility Win8 -ExecutionTimeLimit 0

$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "ToriDaemon" `
  -Action $taskAction `
  -Trigger $taskTrigger `
  -Settings $taskSettings `
  -Principal $taskPrincipal `
  -Description "Tori Daemon 24/7 Scanner"

# Verify
Get-ScheduledTask -TaskName "ToriDaemon"
```

### Automated Startup (Linux/WSL)

Add to crontab:

```bash
# Run every reboot
@reboot /usr/bin/pwsh -NoProfile -ExecutionPolicy Bypass -File /path/to/agents/Start-ToriDaemon.ps1 >> /path/to/journal/tori_startup.log 2>&1
```

---

## Operations

### Check Daemon Status

```powershell
# View all daemon jobs
Get-Job -Name "ToriDaemon*"

# View specific job
$job = Get-Job -Name "ToriDaemon*" | Select-Object -First 1
$job | Format-List

# View heartbeat
Get-Content journal/tori_daemon_heartbeat.txt | ConvertFrom-Json

# View current state
Get-Content journal/tori_daemon_state.json | ConvertFrom-Json | Select-Object -Property timestamp, @{N='active_setups';E={$_.active_setups.Count}}, @{N='closed_trades';E={$_.closed_trades.Count}}
```

### View Logs

```powershell
# Last 50 lines of daemon log
Get-Content journal/tori_daemon.log -Tail 50

# Last 20 lines of watchdog log
Get-Content journal/tori_daemon_watchdog.log -Tail 20

# Search for errors
Select-String "ERROR" journal/tori_daemon.log

# Monitor in real-time (PowerShell 3+)
Get-Content journal/tori_daemon.log -Wait
```

### Generate Reports

```powershell
# Generate all reports (HTML, JSON, CSV)
. agents/tori_daemon_reporter.ps1
Export-ToriReports

# View HTML dashboard
Start-Process journal/reports/tori_dashboard.html

# Export specific format
Export-ToriReports -ReportType html  # or json, csv
```

### Stop Daemon

```powershell
# Graceful shutdown
.\Stop-ToriDaemon.ps1

# Force kill (if hung)
.\Stop-ToriDaemon.ps1 -Force

# Stop and generate final report
.\Stop-ToriDaemon.ps1 -GenerateReport
```

---

## Troubleshooting

### Daemon Won't Start

**Check prerequisites:**

```powershell
# Verify config exists
Test-Path agents/config.local.ps1

# Verify libraries exist
ls agents/lib_tori*.ps1 agents/lib_coinex.ps1

# Check for existing daemon
Get-Job -Name "ToriDaemon*"

# If running, stop it first
.\Stop-ToriDaemon.ps1
```

**Check startup log:**

```powershell
Get-Content journal/tori_daemon_startup.log -Tail 50
```

**Common issues:**

| Error | Solution |
|-------|----------|
| "lib_coinex.ps1 not found" | Copy missing files to `agents/` directory |
| "Config file not found" | Create `agents/config.local.ps1` with API keys |
| "Port already in use" | Stop existing daemon: `.\Stop-ToriDaemon.ps1 -Force` |
| "Permission denied" | Run PowerShell as Administrator |

### Daemon Crashes Frequently

**Check watchdog logs:**

```powershell
Get-Content journal/tori_daemon_watchdog.log -Tail 100 | Select-String "ERROR|RESTART"
```

**Check restart history:**

```powershell
Get-Content journal/tori_daemon_restarts.json | ConvertFrom-Json | Select-Object -Property total_restarts, restarts
```

**Common causes:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Heartbeat stale" | API timeout | Increase `SCAN_INTERVAL_MINUTES`, check network |
| "CoinEx API error" | Rate limited | Increase `API_RATE_LIMIT_DELAY_MS` |
| "JSON parse error" | Corrupt state file | Delete `journal/tori_daemon_state.json`, restart |
| "Out of memory" | Unchecked growth | Clear old trades in state file, restart |

### No Alerts on Telegram

**Check configuration:**

```powershell
$env:TELEGRAM_BOT_TOKEN       # Should be set
$env:TELEGRAM_CHAT_ID         # Should be set

# Test send manually
. agents/tori_telegram_alerts.ps1
Send-TelegramMessage -Message "Test message"
```

**Check alert logs:**

```powershell
Get-Content journal/tori_daemon.log | Select-String "Telegram"
```

**Common issues:**

- Bot token invalid → Check token in config
- Chat ID wrong → Check bot is member of chat
- Network blocked → Verify outbound HTTPS to api.telegram.org

### Memory/Disk Growing

**State file getting large:**

```powershell
# Check file size
(Get-Item journal/tori_daemon_state.json).Length / 1MB

# If > 50MB, trim closed trades
# Edit state file JSON, keep only last 500 closed trades

# Or restart daemon (creates fresh state)
.\Stop-ToriDaemon.ps1
.\Start-ToriDaemon.ps1
```

**Logs filling disk:**

```powershell
# Archive old logs
tar -czf journal/logs_$(Get-Date -Format yyyyMMdd).tar.gz journal/tori_*.log

# Clear archived logs older than 30 days
Get-ChildItem journal/logs_*.tar.gz | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
```

---

## Performance Tuning

### Optimize Scan Cycles

**For faster updates (every 2 hours):**

```powershell
# Edit tori_daemon_24h.ps1
$script:SCAN_INTERVAL_MINUTES = 120    # 2 hours

# Reduce pairs per scan
$script:MAX_PAIRS_PER_SCAN = 75       # Half as many

# Reduce timeframes
$script:TIMEFRAMES = @("1D", "4H")    # Skip 1W, 1H
```

**Expected impact:**
- ✅ More frequent updates
- ❌ ~2x more API calls
- ❌ Risk of rate limiting

### Optimize for High-Latency Networks

```powershell
# Increase timeouts
$script:API_RATE_LIMIT_DELAY_MS = 500    # 500ms between calls

# Reduce concurrent pairs
$script:MAX_CONCURRENT_PAIRS = 5         # Lower parallelism

# Reduce data
$script:CANDLES_LIMIT = 100             # 100 candles instead of 300
```

### Monitor Resource Usage

```powershell
# Check memory
(Get-Process powershell | Where-Object { $_.Name -match "ToriDaemon" } | 
  Measure-Object -Property WorkingSet -Sum).Sum / 1MB   # MB

# Check CPU over time
Get-Counter '\Process(powershell#*)\% Processor Time' -SampleInterval 5 -MaxSamples 10 | 
  Select-Object -ExpandProperty CounterSamples |
  Where-Object { $_.InstanceName -match "ToriDaemon" } |
  Select-Object -ExpandProperty CookedValue
```

**Targets:**
- Memory: < 200MB
- CPU: < 5% when idle (scanning), < 50% during scan
- Disk write: < 100KB per cycle

---

## Monitoring

### Health Check Script

```powershell
# health_check.ps1

function Get-ToriHealth {
    param([switch]$Verbose)

    $daemonJob = Get-Job -Name "ToriDaemon*" -ErrorAction SilentlyContinue | 
                 Where-Object { $_.State -eq "Running" } | 
                 Select-Object -First 1

    if (-not $daemonJob) {
        return @{ status = "DOWN"; message = "No running daemon" }
    }

    $heartbeat = Get-Content journal/tori_daemon_heartbeat.txt -ErrorAction SilentlyContinue | 
                 ConvertFrom-Json -ErrorAction SilentlyContinue

    if (-not $heartbeat) {
        return @{ status = "WARNING"; message = "No heartbeat" }
    }

    $heartbeatAge = (Get-Date) - [DateTime]::Parse($heartbeat.timestamp)
    $isStale = $heartbeatAge.TotalSeconds -gt 600

    $state = Get-Content journal/tori_daemon_state.json -ErrorAction SilentlyContinue | 
             ConvertFrom-Json -ErrorAction SilentlyContinue

    return @{
        status = if ($isStale) { "STALE" } else { "OK" }
        heartbeat_age_sec = [Math]::Round($heartbeatAge.TotalSeconds)
        scans_completed = $heartbeat.scans_completed
        active_setups = $state.active_setups.Count
        closed_trades = $state.closed_trades.Count
        total_pnl = $state.performance.total_pnl
        win_rate = $state.performance.win_rate
        job_id = $daemonJob.Id
        job_name = $daemonJob.Name
        uptime_min = [Math]::Round(((Get-Date) - $daemonJob.PSBeginTime).TotalMinutes)
    }
}

# Usage
$health = Get-ToriHealth
$health | Format-Table

# For monitoring systems
if ($health.status -eq "OK") { exit 0 } else { exit 1 }
```

### Prometheus Metrics Export

```powershell
# Export metrics for Prometheus scraper
function Export-PrometheusMetrics {
    $state = Get-Content journal/tori_daemon_state.json | ConvertFrom-Json
    $heartbeat = Get-Content journal/tori_daemon_heartbeat.txt | ConvertFrom-Json

    $metrics = @"
# HELP tori_daemon_active_setups Number of open setups
# TYPE tori_daemon_active_setups gauge
tori_daemon_active_setups $($state.active_setups.Count)

# HELP tori_daemon_closed_trades Total closed trades
# TYPE tori_daemon_closed_trades counter
tori_daemon_closed_trades $($state.closed_trades.Count)

# HELP tori_daemon_total_pnl Total P&L in USDT
# TYPE tori_daemon_total_pnl gauge
tori_daemon_total_pnl $($state.performance.total_pnl)

# HELP tori_daemon_win_rate Win rate (0-1)
# TYPE tori_daemon_win_rate gauge
tori_daemon_win_rate $($state.performance.win_rate)

# HELP tori_daemon_scans_total Total scan cycles
# TYPE tori_daemon_scans_total counter
tori_daemon_scans_total $($heartbeat.scans_completed)
"@

    Set-Content -Path journal/tori_metrics.txt -Value $metrics -Encoding UTF8
}

# Run periodically
Export-PrometheusMetrics
```

---

## Disaster Recovery

### Backup State

```powershell
# Daily backup
$timestamp = Get-Date -Format "yyyyMMdd"
Copy-Item journal/tori_daemon_state.json `
  journal/backups/tori_daemon_state_$timestamp.json
```

### Restore from Backup

```powershell
# Stop daemon first
.\Stop-ToriDaemon.ps1

# Restore state
Copy-Item journal/backups/tori_daemon_state_20260707.json `
  journal/tori_daemon_state.json

# Restart
.\Start-ToriDaemon.ps1
```

### Rebuild State from History

```powershell
# If state corrupted, rebuild from closed trades log
# (assuming CSV export exists in journal/reports/)

$trades = Import-Csv journal/reports/tori_trades.csv

$state = @{
    timestamp = Get-Date -Format "o"
    active_setups = @()
    closed_trades = $trades
    performance = @{
        total_scans = 0
        total_pnl = ($trades | Measure-Object -Property unrealized_pnl -Sum).Sum
        win_rate = (($trades | Where-Object { $_.unrealized_pnl -gt 0 }).Count / $trades.Count)
    }
} | ConvertTo-Json

Set-Content journal/tori_daemon_state.json -Value $state
```

### Emergency Shutdown

```powershell
# If daemon hung and won't respond to graceful shutdown

# Find process
Get-Process powershell | Where-Object { $_.CommandLine -match "tori_daemon" }

# Kill by ID
Stop-Process -Id 12345 -Force

# Clean up
Remove-Item journal/tori_daemon.lock -Force
Remove-Item journal/tori_daemon_heartbeat.txt -Force

# Restart
.\Start-ToriDaemon.ps1
```

---

## Security Considerations

### API Key Protection

✅ **DO:**
- Store in `config.local.ps1` (git-ignored)
- Use environment variables in production
- Rotate keys periodically

❌ **DON'T:**
- Commit keys to git
- Log API keys
- Share config files

### Log Sanitization

```powershell
# Remove sensitive data from logs
$logContent = Get-Content journal/tori_daemon.log -Raw
$sanitized = $logContent -replace '[A-Za-z0-9]{32,}', 'REDACTED'
Set-Content journal/tori_daemon_public.log -Value $sanitized
```

### Network Security

- Use HTTPS only (CoinEx API enforced)
- Validate SSL certificates
- Use VPN if running from public network
- Firewall: restrict outbound to CoinEx + Telegram IPs

---

## Support & Troubleshooting Matrix

| Symptom | Probable Cause | First Step | Fix |
|---------|---|---|---|
| No scans executing | Config missing | Check `config.local.ps1` | Create config with API keys |
| API errors (40x) | Rate limited | Check delay settings | Increase `API_RATE_LIMIT_DELAY_MS` |
| Memory grows unbounded | State file leak | Check file size | Trim closed trades, restart |
| Telegram not sending | Token invalid | Test manually | Verify `TELEGRAM_BOT_TOKEN` |
| Daemon crashes every hour | Timeout | Check logs | Increase timeout in API calls |
| High CPU usage | Too many pairs | Monitor % | Reduce `MAX_PAIRS_PER_SCAN` |
| Disk filling | Log spam | Check log size | Archive old logs, rotate |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-07-08 | Initial production release |

---

## License & Disclaimer

**Educational use only.** Trading decisions based on automated signals carry substantial risk. Always validate signals manually before execution. Past performance does not guarantee future results.

---

## Contact & Resources

- **Documentation:** `docs/TORI_DAEMON_DEPLOYMENT.md`
- **Source Code:** `agents/tori_daemon_*.ps1`
- **State Format:** `journal/tori_daemon_state.json`
- **Logs:** `journal/tori_daemon*.log`
- **CoinEx API:** https://viabtc.github.io/coinex_api_en_doc/
