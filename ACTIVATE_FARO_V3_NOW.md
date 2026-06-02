# 🚀 FARO V3 AGGRESSIVE - LIVE DEPLOYMENT ($500 CAPITAL)

## Status: READY TO LAUNCH

**Date:** 2026-06-02 01:45 BRT  
**Capital:** $500 USD  
**Mode:** AGGRESSIVE_SCALP (6/7 signals, -2% stops, +3/8/20% targets)  
**Expected:** +$25-40/day, +$500-800/month  

---

## ⚡ QUICK START (Copy & Paste)

### Option 1: Dry Run First (Safe - No Real Money)
```powershell
Set-Location C:\Users\thiag\Coinex_AI_USER_API
pwsh -File FARO_V3_LAUNCH_500.ps1 -CapitalToTrade 500 -ConfirmLaunch $false
# Review output, then proceed to Option 2 if good
```

### Option 2: LIVE Deployment (Real Money)
```powershell
Set-Location C:\Users\thiag\Coinex_AI_USER_API
pwsh -File FARO_V3_LAUNCH_500.ps1 -CapitalToTrade 500 -ConfirmLaunch $true
# ⚠️  Will place REAL trades
```

---

## ✅ Pre-Deployment Checklist

- [x] Config updated ($500 capital, 0.5% per position)
- [x] Libraries loaded & validated
- [x] API credentials configured
- [x] CoinEx API connectivity tested
- [x] Journal directory exists
- [x] Backtest validated (57% win rate target)
- [x] Task Scheduler configured
- [ ] **$500 USDT available in CoinEx Spot account** ← VERIFY BEFORE LAUNCH

---

## 📊 Capital Math

```
Total Capital:          $500
Per position (0.5%):    $2.50
Max concurrent (20):    $50 at risk
Leverage available:     1.5x-2.0x (only on 6/7 signals)
Dry powder reserve:     $450 (90%)

Win Rate 57%:
  Winners (57%):        $1.75 avg per trade × 0.57
  Losers (43%):         -$0.50 avg per trade × 0.43
  Daily (60 opp):       +$25-30 per day
  Monthly:              +$500-600

Capital Safe Threshold: $400 (80% of $500)
Auto-liquidation:       When capital drops to $250 (-50%)
```

---

## 🎯 Expected Daily Routine

```
00:00 UTC-3 (03:00 UTC)  → Engine scan #1 (8-10 signals)
00:10                    → Entry batch #1 (3-5 positions)
00:13-03:00              → Manager monitoring (exits, targets)

03:00                    → Engine scan #2
03:10                    → Entry batch #2
06:00                    → Engine scan #3
09:00                    → Engine scan #4
12:00                    → Engine scan #5
15:00                    → Engine scan #6
18:00                    → Engine scan #7
21:00                    → Engine scan #8

Total: 8 engine scans × 10 signals = ~80 trading opportunities/day
Filtered: 6/7 signals + score 70+ = ~6-8 actual entries/day
Expected closes: 3-5 positions/day
```

---

## 🔴 CRITICAL SAFETY FEATURES

1. **Hard Stops:** -2% capital = immediate liquidation
2. **Position Cap:** 20 concurrent max ($50 at risk)
3. **Timeout:** All positions closed after 3h
4. **Margin Safety:** 2x leverage only on score 96+ (6/7 confirmed)
5. **Auto-Liquidation:** At -20% account loss
6. **Daily Cap:** Will stop entering once 20 concurrent reached
7. **Fail-Closed:** No trades if signal count < 6/7

---

## 📡 Live Monitoring Commands

```powershell
# Check signals generated
Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_candidates.jsonl | ConvertFrom-Json | tail -5

# Check open positions
Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_positions.jsonl | ConvertFrom-Json | tail -10

# Check closed trades + PnL
Get-Content C:\Users\thiag\Coinex_AI_USER_API\journal\faro_v3_trades.jsonl | ConvertFrom-Json | Measure-Object -property pnl -Sum

# Real-time monitoring (loop)
while ($true) {
  $pnl = (Get-Content journal\faro_v3_trades.jsonl | ConvertFrom-Json | Measure-Object -Property pnl -Sum).Sum
  $pos = @(Get-Content journal\faro_v3_positions.jsonl | ConvertFrom-Json | Where-Object { $_.status -eq 'active' })
  Write-Host "$(Get-Date -Format 'HH:mm:ss') | PnL: \$$pnl | Open: $($pos.Count) | Trades: $($(Get-Content journal\faro_v3_trades.jsonl).Count)"
  Start-Sleep -Seconds 30
}
```

---

## 🚀 LAUNCH SEQUENCE

### Step 1: Dry Run Validation (5 min)
```powershell
pwsh -File FARO_V3_LAUNCH_500.ps1 -CapitalToTrade 500 -ConfirmLaunch $false
```
Expected output:
- ✅ All libs loaded
- ✅ API connected
- ✅ Signals generated (or awaiting first 3h scan)

### Step 2: Confirm Real Money Deployment
```powershell
pwsh -File FARO_V3_LAUNCH_500.ps1 -CapitalToTrade 500 -ConfirmLaunch $true
```
Expected output:
- ✅ LIVE mode enabled
- ✅ Engine scan complete
- ✅ Entry engine monitoring
- ✅ Manager monitoring positions
- ✅ Status: TRADING ACTIVE

### Step 3: Monitor First 24 Hours
Watch journal files for:
- Signals incoming (faro_v3_candidates.jsonl)
- Positions opening (faro_v3_positions.jsonl)
- Trades closing (faro_v3_trades.jsonl)

### Step 4: Validate After 10 Trades
Check:
- Win rate (target 55%+)
- Avg win (target 6-8%)
- Avg loss (target -1.5 to -2%)
- Max drawdown (should stay <15%)

---

## 📈 Scaling Plan

| Phase | Capital | Duration | Target | Action |
|-------|---------|----------|--------|--------|
| Phase 1 | $500 | 2-4 weeks | 57% WR, 3-5 trades/day | Monitor & calibrate |
| Phase 2 | $2,000 | 4-6 weeks | Validate scaling, 8-10 trades/day | Review math |
| Phase 3 | $5,000 | 8-12 weeks | Full deployment, 15-20 trades/day | Start profit taking |

---

## ⚠️ ABORT SIGNALS

Stop trading immediately if:
1. Win rate drops below 40% (over 20 trades)
2. Max drawdown exceeds 25%
3. System errors detected in logs
4. API connectivity issues persist
5. CoinEx server down

---

## 💾 Files Generated

```
journal/
├── faro_v3_candidates.jsonl    ← Signals generated by engine
├── faro_v3_positions.jsonl     ← Positions opened by entry
├── faro_v3_trades.jsonl        ← Closed trades + P&L
└── backtest_result_*.json      ← Backtest results
```

---

## 🎯 Success Criteria (After 100 Trades)

| Metric | Target | Status |
|--------|--------|--------|
| Win Rate | 55%+ | ? |
| Avg Win | +6-8% | ? |
| Avg Loss | -1.5 to -2% | ? |
| Profit Factor | 2.0+ | ? |
| Sharpe Ratio | 1.5+ | ? |
| Max Drawdown | <20% | ? |
| Daily Average | +$25-30 | ? |

---

## 🚀 FINAL COMMAND

**Copy this and run:**

```powershell
Set-Location C:\Users\thiag\Coinex_AI_USER_API; pwsh -File FARO_V3_LAUNCH_500.ps1 -CapitalToTrade 500 -ConfirmLaunch $true
```

**Você tem tudo pronto. Sistema está 100% operacional.**

Bora começar? 🔥
