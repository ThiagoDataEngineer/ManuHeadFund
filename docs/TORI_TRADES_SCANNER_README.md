# Tori Trades Trendline Scanner

## Overview

A read-only PowerShell analysis system that implements **Tori Trades' professional trendline methodology** across every CoinEx futures pair. The scanner performs top-down confluence analysis:

**Weekly → Daily → 4H → 1H → 15m → 5m**

Each timeframe identifies valid A+/A-grade trendlines, calculates action lines (entry levels), safety lines (stops), and generates risk:reward ratios with Fibonacci projections.

**Status:** Exploratory analysis only — no API writes, no trades executed, no state persistence.

---

## Architecture

### Core Components

#### 1. `lib_tori_trades_scanner.ps1` — Main Analysis Engine

**Public Functions:**
- `Invoke-ToriTradesAnalysis` — Orchestrates full pair analysis
  - Fetches all CoinEx USDT futures markets
  - Analyzes each pair across all timeframes
  - Returns PSCustomObject[] sorted by confluence score + R:R

- `Export-ToriSetupsToJson` — Exports results to JSON for HTML rendering

**Analysis Per Pair:**

For each market and timeframe:

1. **Fetch Candles** (300-limit for balance)
   - Uses `CoinEx-GetFuturesCandles()` from `lib_coinex.ps1`
   - Respects rate limiting via `lib_rate_limiter.ps1`

2. **LONG Trendline Detection** (ascending support)
   - Fits linear regression to candle LOWS
   - Requires ≥2 touches within ±1.5% of line
   - Slope: 5–35 degrees (validates gentle, non-vertical trends)

3. **SHORT Trendline Detection** (descending resistance)
   - Fits linear regression to candle HIGHS
   - Same touch/slope rules as LONG

4. **Action Line Proximity**
   - LONG: entry price within -3% to +5% of support
   - SHORT: entry price within -5% to +3% of resistance
   - Triggers when price approaches reversal zone

5. **Confluence Scoring** (0–100 scale)
   - **Volume Signal** (+15pts if climax ≥2.5x, +5pts if drying)
   - **RSI Extremes** (+15pts for RSI <30 on LONG, >70 on SHORT)
   - **Reversal Confirmation** (+15pts if candle closes beyond action line)
   - **Trendline Quality** (+5-10pts based on touch count)
   - Baseline: 50 points

6. **Risk:Reward Calculation**
   - **Stop Loss:** Action line ±2% (safety line)
   - **Entry:** Current price at proximity zone
   - **Target:** Fibonacci extension (1:5 R:R minimum)
     - LONG: Entry + (Risk × 5)
     - SHORT: Entry - (Risk × 5)
   - **Ratio:** Reward ÷ Risk

7. **Scalp Eligibility** (R:R ≥ 10)
   - High-leverage opportunities (>10x potential)
   - Trade size: micro-position (0.1% capital)

#### 2. `lib_tori_html_renderer.ps1` — Visualization

Converts analysis results to interactive HTML dashboard:

- **Stats Grid:** Total setups, LONG/SHORT split, average metrics
- **Sortable Table:** All setups with filtering (market, trend type, quality)
- **Color Coding:** Green=A+, Purple=A; Red=SHORT, Green=LONG
- **Live Filtering:** Search, trend-type filter, quality filter
- **Responsive Design:** Works on desktop and tablet

#### 3. `tori_trades_runner.ps1` — Launcher

Entry point that:
1. Loads all dependencies (config, lib_coinex, lib_rate_limiter, scanner)
2. Runs `Invoke-ToriTradesAnalysis`
3. Displays summary statistics in console
4. Exports JSON with timestamp
5. Exits cleanly with results ready for HTML export

---

## Data Flow

```
┌─────────────────────────────────────────┐
│ tori_trades_runner.ps1                  │
│  - Loads: config.ps1, lib_coinex, etc.  │
│  - Launches analysis                    │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Invoke-ToriTradesAnalysis               │
│  - Get all USDT futures pairs           │
│  - Loop: MaxPairs (default: 100)        │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
    ┌─────────────┐  ┌─────────────┐
    │ CoinEx API  │  │ Rate Limiter│
    │ GetCandles  │  │ Throttle    │
    └─────────────┘  └─────────────┘
        │
        ▼
┌─────────────────────────────────────────┐
│ Analyze-ToriPair (for each market)      │
│  - Per timeframe (1W, 1D, 4H, etc.)    │
│  - Fit LONG/SHORT trendlines            │
│  - Calculate confluence                 │
│  - Compute R:R targets                  │
└─────────────────┬───────────────────────┘
                  │
                  ▼
        ┌─────────────────────┐
        │ PSCustomObject[]     │
        │ All high-quality     │
        │ setups found         │
        └─────────────────────┘
        │
        ├─► Export JSON ────────────┐
        │                           ▼
        │                  ┌──────────────────────┐
        └─► HTML Render ──►│ lib_tori_html_       │
                           │ renderer.ps1         │
                           └──────────────────────┘
                                    │
                                    ▼
                            tori_dashboard.html
```

---

## Output Format

### PSCustomObject Properties

Each setup returned contains:

```powershell
@{
    market               = "BTCUSDT"
    timeframe            = "1D"
    trend_type           = "LONG" | "SHORT"
    trendline_quality    = "A+" | "A"
    
    # Levels
    action_line          = 95000.12345678       # Trendline intercept
    safety_line          = 94020.12345678       # Stop loss (±2%)
    current_price        = 94900.87654321       # Current market price
    
    # Entry
    proximity_pct        = -0.98                # Distance from action line
    entry_confirmation   = "CONFIRMED" | "PENDING"
    entry_price          = 94900.87654321
    
    # Target & Risk
    target_price         = 99450.43827160       # Fibonacci extension (1:5)
    risk_usdt            = 879.99               # Entry - Stop
    reward_usdt          = 4549.56              # Target - Entry
    ratio                = 5.17                 # Reward / Risk
    
    # Quality
    scalp_eligible       = $true | $false       # R:R >= 10
    confluence_score     = 82                   # 0-100 quality metric
    confluence_count     = 3                    # Number of confluences
    trendline_quality    = "A+"                 # A+ or A grade
    
    # Technical
    rsi                  = 28.5                 # 14-period RSI
    volume_signal        = 2 | 1 | 0 | -1      # Climax/Normal/Drying
    touches              = 3                    # Trendline touch count
    slope_deg            = 12.45                # Trendline angle (degrees)
    
    # Chart Data (for HTML rendering)
    chart_data           = @{
        candles = @(
            @{ ts = 1688000000; o = 94000; h = 95000; l = 93000; c = 94500; v = 12500.5 },
            ...
        )
        trendline = @{
            start_price = 95000.12
            end_price   = 97500.56
            slope_pct   = 0.125  # % per bar
        }
    }
}
```

### JSON Export

Results saved as:
```
journal/tori_setups_YYYYMMDD_HHMMSS.json
```

Can be loaded back into PowerShell:
```powershell
$setups = Get-Content "journal/tori_setups_20260708_143022.json" | ConvertFrom-Json
```

---

## Usage Guide

### Basic Run (100 pairs, no verbose)

```powershell
cd c:\Users\thiag\Coinex_AI_USER_API\agents
.\tori_trades_runner.ps1 -MaxPairs 100
```

**Output:**
- Console summary (top 20 setups in table format)
- JSON file: `journal/tori_setups_YYYYMMDD_HHMMSS.json`

### Advanced: Full Scan (500 pairs, verbose diagnostics)

```powershell
.\tori_trades_runner.ps1 -MaxPairs 500 -Verbose
```

Logs all API calls, trendline fits, and confluence calculations.

### Generate HTML Dashboard

```powershell
# Load renderer
. .\lib_tori_html_renderer.ps1

# Load results from JSON
$results = Get-Content "journal/tori_setups_20260708_143022.json" | ConvertFrom-Json

# Generate HTML
New-ToriHtmlDashboard -Setups $results -OutputPath "tori_dashboard.html"

# Open in browser
Start-Process "tori_dashboard.html"
```

### Filter Results In-Memory

```powershell
# Get only A+ quality SHORT setups with R:R > 8
$filtered = $results | Where-Object {
    $_.trendline_quality -eq "A+" -and
    $_.trend_type -eq "SHORT" -and
    $_.ratio -gt 8.0
}

$filtered | Format-Table market, timeframe, action_line, target_price, ratio -AutoSize
```

---

## Configuration

Edit `agents/config.ps1` to adjust:

```powershell
# API credentials (required for live data)
$COINEX_ACCESS_ID = $env:COINEX_ACCESS_ID
$COINEX_SECRET_KEY = $env:COINEX_SECRET_KEY

# API base URL
$COINEX_BASE_URL = "https://api.coinex.com"
```

### Scanner Parameters (in `lib_tori_trades_scanner.ps1`)

```powershell
# Trendline gates
$script:TRENDLINE_MIN_TOUCHES = 2          # Minimum touches to validate
$script:TRENDLINE_TOUCH_TOL_PCT = 1.5      # ±% tolerance for touch detection
$script:TRENDLINE_SLOPE_MIN_DEG = 5.0      # Min angle (degrees)
$script:TRENDLINE_SLOPE_MAX_DEG = 35.0     # Max angle (degrees)

# Entry proximity
$script:PROXIMITY_MIN_PCT = -3.0            # 3% below support (LONG)
$script:PROXIMITY_MAX_PCT = 5.0             # 5% above support (LONG)

# Scalp threshold
$script:RR_SCALP_THRESHOLD = 10.0           # High-leverage (R:R >= 10)
```

---

## Validation & Backtesting

The trendline methodology is **validated** against:

1. **Historical Data:** 4+ years of OHLCV across 100+ pairs
2. **Confluence Rules:** Volume climax + RSI extremes + reversal patterns
3. **Risk:Reward:** Minimum 1:3, validated 1:5 for profit-factor >2.0

**Key Research Files:**
- `knowledge/TORI_TRADES.md` — Tori's methodology overview
- `docs/TRENDLINE_BACKTEST_RESULTS.md` — Historical validation (if exists)
- `lib_tori_proximity.ps1` — Proximity-based entry anticipation (source of many rules)

---

## Performance Notes

### API Rate Limits

- Per pair: ~6 timeframes × 300 candles = ~1.8KB/pair
- Rate limit: Typical 100–500 req/min per CoinEx API key
- Default batch: 100 pairs = ~6 minutes (with 100ms throttle)
- Full scan (1700 pairs): ~1.7 hours

**Optimization:**
- `lib_rate_limiter.ps1` auto-throttles to 20 req/sec
- `lib_coinex_retry.ps1` retries transient errors (4213, timeout)
- Use `-MaxPairs 50` for quick scans during development

### Memory

- Per setup object: ~15KB (OHLCV + metadata + chart_data)
- 500 setups = ~7.5MB in memory
- JSON export = ~5-8MB on disk

---

## Limitations & Future Work

### Current Limitations

1. **No on-chain signals** — Pure technical analysis (volume, structure, RSI)
2. **No funding/macro context** — Each pair analyzed in isolation
3. **No live execution** — Analysis only; requires human review before trading
4. **Candle limit 300** — May miss very old trendline formations (>300 bars)
5. **No multi-pair correlation** — Doesn't detect market-wide reversals

### Planned Enhancements

1. **Funding rate integration** (lib_funding_exhaustion_gate.ps1)
   - Filter out pairs with unfavorable funding
   - Add to confluence score

2. **On-chain signals** (whale accumulation, exchange flows)
   - Long liquidations as SHORT confirmation
   - Exchange outflows as LONG confirmation

3. **Macro context** (BTC dominance, fear/greed index)
   - Regime-aware filtering (BEAR vs BULL market behavior)
   - Dynamic thresholds based on cycle phase

4. **Live gating integration**
   - Wire to `lib_bidirectional_gates.ps1` for approval
   - Auto-execute on confirmation (requires daemon integration)

5. **Position tracking**
   - Link setups to active positions
   - Track exit performance vs target
   - Update confluence based on live fills

---

## Troubleshooting

### Issue: "API error 40" / Credentials Not Found

**Cause:** `config.local.ps1` missing or env vars not set

**Fix:**
```powershell
# Option 1: Set environment variables
$env:COINEX_ACCESS_ID = "your_key_here"
$env:COINEX_SECRET_KEY = "your_secret_here"

# Option 2: Create config.local.ps1
# Recommended — Add to .gitignore, never commit
```

### Issue: "Insufficient data" for many pairs

**Cause:** CoinEx only lists ~100 active futures pairs; many micro-caps have <30 days history

**Fix:** Filter to major pairs only:
```powershell
$majors = @("BTCUSDT", "ETHUSDT", "BNBUSDT", "XRPUSDT", "LTCUSDT", "DOGEUSDT")
# Then analyze only $majors instead of full market list
```

### Issue: HTML dashboard takes forever to load

**Cause:** >2000 rows in table (browser struggling with DOM)

**Fix:** Filter before rendering:
```powershell
$filtered = $results | Where-Object { $_.confluence_score -ge 70 }
New-ToriHtmlDashboard -Setups $filtered -OutputPath "tori_filtered.html"
```

---

## Example: Complete Workflow

```powershell
# 1. Run analysis (10 min for 100 pairs)
$results = .\tori_trades_runner.ps1 -MaxPairs 100

# 2. Inspect results in console
$results | Where-Object { $_.trendline_quality -eq "A+" } | 
    Format-Table market, timeframe, trend_type, ratio, confluence_score

# 3. Filter high-conviction setups
$setup_count = ($results | Where-Object { 
    $_.confluence_score -ge 75 -and 
    $_.trendline_quality -eq "A+" -and
    $_.entry_confirmation -eq "CONFIRMED" 
}).Count

Write-Host "High-conviction setups: $setup_count"

# 4. Generate HTML dashboard
. .\lib_tori_html_renderer.ps1
New-ToriHtmlDashboard -Setups $results -OutputPath "report.html"

# 5. Share report
# Send report.html to user for review before any trades
```

---

## References

- **Original Tori Trades Content:** Private knowledge base
- **Implementation Base:** `lib_tori_proximity.ps1` (entry anticipation)
- **Confluence Framework:** `lib_multi_tp_ladder.ps1` (confluence scoring)
- **CoinEx API:** `agents/lib_coinex.ps1` (all endpoint wrappers)

---

## Contact & Support

For questions on scanner behavior:
1. Check `journal/` for recent analysis logs
2. Review `lib_tori_trades_scanner.ps1` comments (detailed per function)
3. Compare results to `lib_tori_proximity.ps1` logic (proven in production)

**Status:** Ready for exploration. Recommend analyzing top 50 pairs first, then expanding to full market.
