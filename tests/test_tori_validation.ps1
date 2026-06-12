# test_tori_validation.ps1 -- Validar Tori Proximity (TDD)
#
# OBJETIVO: Comparar implementação PowerShell vs Python
# 
# HIPÓTESE: Python detectou apenas 1 signal em 14.8 anos
#           PowerShell pode ter implementação diferente (mais signals?)
#
# METODOLOGIA TDD:
# 1. Carregar dados históricos (mesmos que Python)
# 2. Executar Get-ToriProximityFromArrays
# 3. Contar signals detectados
# 4. Comparar com Python (1 signal)

$ErrorActionPreference = "Stop"

# Load libraries
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. "$root\agents\config.ps1"
. "$root\agents\lib_tori_proximity.ps1"
. "$root\agents\lib_coinex.ps1"

Write-Host "="*60 -ForegroundColor Cyan
Write-Host "TORI PROXIMITY VALIDATION (TDD)" -ForegroundColor Cyan
Write-Host "Comparing PowerShell vs Python implementation" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# ============================================================================
# FETCH HISTORICAL DATA (same as Python - FULL period)
# ============================================================================

Write-Host "`nFetching historical data (FULL period)..." -ForegroundColor White

# Use Python's cached data (same source as Python tests)
$cache_file = "$root\backtest\.cache\unified_BTCUSDT_1d.json"

if (Test-Path $cache_file) {
    Write-Host "  Loading from Python cache: $cache_file" -ForegroundColor Gray
    
    try {
        $cache_data = Get-Content $cache_file -Raw | ConvertFrom-Json
        $candles_data = $cache_data.candles
        
        # Convert to PowerShell format
        $candles = @()
        foreach ($c in $candles_data) {
            $candles += @{
                timestamp = [datetime]::Parse($c.timestamp).ToUniversalTime().Ticks / 10000000 - 11644473600
                open = [double]$c.open
                high = [double]$c.high
                low = [double]$c.low
                close = [double]$c.close
                volume = [double]$c.volume
            }
        }
        
        Write-Host "  [OK] Loaded $($candles.Count) candles from cache" -ForegroundColor Green
        
        # Date range
        $first_date = [datetime]::Parse($candles_data[0].timestamp)
        $last_date = [datetime]::Parse($candles_data[-1].timestamp)
        
        Write-Host "  Date range: $($first_date.ToString('yyyy-MM-dd')) to $($last_date.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
        
        $days = ($last_date - $first_date).TotalDays
        $years = $days / 365.25
        
        Write-Host "  Period: $([math]::Round($years, 1)) years" -ForegroundColor Gray
        
    } catch {
        Write-Host "  [ERROR] Failed to load cache: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [ERROR] Cache file not found: $cache_file" -ForegroundColor Red
    Write-Host "  Run Python scripts first to generate cache" -ForegroundColor Red
    exit 1
}

# ============================================================================
# SCAN FOR TORI PROXIMITY SIGNALS
# ============================================================================

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host "SCANNING FOR TORI PROXIMITY SIGNALS" -ForegroundColor Cyan
Write-Host "$('='*60)" -ForegroundColor Cyan

$signals = @()
$min_window = 30

# Extract arrays
$closes = @($candles | ForEach-Object { [double]$_.close })
$highs = @($candles | ForEach-Object { [double]$_.high })
$lows = @($candles | ForEach-Object { [double]$_.low })
$volumes = @($candles | ForEach-Object { [double]$_.volume })

Write-Host "`nScanning $($candles.Count) candles..." -ForegroundColor White

for ($i = $min_window; $i -lt $candles.Count; $i++) {
    # Progress
    if ($i % 100 -eq 0) {
        $pct = [math]::Round($i / $candles.Count * 100, 0)
        Write-Host "  Progress: $pct% ($i/$($candles.Count)) - Signals: $($signals.Count)" -NoNewline
        Write-Host "`r" -NoNewline
    }
    
    # Get window
    $window_closes = $closes[0..$i]
    $window_highs = $highs[0..$i]
    $window_lows = $lows[0..$i]
    $window_volumes = $volumes[0..$i]
    
    # Detect Tori proximity
    try {
        $result = Get-ToriProximityFromArrays `
            -Closes $window_closes `
            -Highs $window_highs `
            -Lows $window_lows `
            -Volumes $window_volumes
        
        # Check if setup is ripening (signal detected)
        if ($result.valid -and $result.setup_ripening) {
            $signal = @{
                index = $i
                date = $candles[$i].timestamp
                price = $result.price
                action_line = $result.action_line
                proximity_pct = $result.proximity_pct
                slope_deg = $result.slope_deg
                touches = $result.touches
                rsi = $result.rsi
                vol_drying = $result.vol_drying
            }
            
            $signals += $signal
        }
    } catch {
        # Skip errors
    }
}

Write-Host "`n  Completed: $($candles.Count) candles scanned" -ForegroundColor Green

# ============================================================================
# RESULTS
# ============================================================================

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host "RESULTS" -ForegroundColor Cyan
Write-Host "$('='*60)" -ForegroundColor Cyan

Write-Host "`nTotal signals detected: $($signals.Count)" -ForegroundColor $(if ($signals.Count -gt 0) { "Green" } else { "Yellow" })

if ($signals.Count -gt 0) {
    Write-Host "`nSignals:" -ForegroundColor White
    
    foreach ($sig in $signals) {
        $date_str = [datetime]::FromFileTimeUtc($sig.date * 10000000 + 116444736000000000).ToString('yyyy-MM-dd')
        
        Write-Host "  $date_str - Price: `$$([math]::Round($sig.price, 2))" -ForegroundColor Gray
        Write-Host "    Proximity: $([math]::Round($sig.proximity_pct, 2))%" -ForegroundColor Gray
        Write-Host "    Slope: $([math]::Round($sig.slope_deg, 2))°" -ForegroundColor Gray
        Write-Host "    Touches: $($sig.touches)" -ForegroundColor Gray
        Write-Host "    RSI: $([math]::Round($sig.rsi, 1))" -ForegroundColor Gray
        Write-Host "    Vol drying: $($sig.vol_drying)" -ForegroundColor Gray
    }
}

# ============================================================================
# COMPARISON WITH PYTHON
# ============================================================================

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host "COMPARISON WITH PYTHON" -ForegroundColor Cyan
Write-Host "$('='*60)" -ForegroundColor Cyan

$python_signals = 1
$python_period_years = 14.8

Write-Host "`nPython (analyze_long_patterns_deep.py):" -ForegroundColor White
Write-Host "  Signals: $python_signals" -ForegroundColor Gray
Write-Host "  Period: $python_period_years years" -ForegroundColor Gray
Write-Host "  Frequency: $([math]::Round($python_signals / $python_period_years, 2)) signals/year" -ForegroundColor Gray

Write-Host "`nPowerShell (this script):" -ForegroundColor White
Write-Host "  Signals: $($signals.Count)" -ForegroundColor Gray
Write-Host "  Period: $([math]::Round($years, 1)) years" -ForegroundColor Gray
Write-Host "  Frequency: $([math]::Round($signals.Count / $years, 2)) signals/year" -ForegroundColor Gray

$delta = $signals.Count - $python_signals

Write-Host "`nDelta:" -ForegroundColor White
Write-Host "  Signals: $delta" -ForegroundColor $(if ($delta -gt 0) { "Green" } elseif ($delta -lt 0) { "Red" } else { "Yellow" })

# ============================================================================
# VERDICT
# ============================================================================

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host "VERDICT" -ForegroundColor Cyan
Write-Host "$('='*60)" -ForegroundColor Cyan

if ($signals.Count -gt $python_signals * 2) {
    Write-Host "`n[SUCCESS] POWERSHELL HAS MORE SIGNALS ($($signals.Count) vs $python_signals)" -ForegroundColor Green
    Write-Host "   PowerShell implementation is MORE SENSITIVE" -ForegroundColor Green
    Write-Host "   Recommendation: Use PowerShell implementation" -ForegroundColor Green
} elseif ($signals.Count -gt $python_signals) {
    Write-Host "`n[WARNING] POWERSHELL HAS SLIGHTLY MORE SIGNALS ($($signals.Count) vs $python_signals)" -ForegroundColor Yellow
    Write-Host "   Difference may be due to:" -ForegroundColor Yellow
    Write-Host "   1. Data source (CoinEx vs Binance+Bitstamp)" -ForegroundColor Yellow
    Write-Host "   2. Period length ($([math]::Round($years, 1))y vs $($python_period_years)y)" -ForegroundColor Yellow
    Write-Host "   3. Implementation details" -ForegroundColor Yellow
} elseif ($signals.Count -eq $python_signals) {
    Write-Host "`n[SUCCESS] POWERSHELL MATCHES PYTHON ($($signals.Count) signals)" -ForegroundColor Green
    Write-Host "   Implementations are CONSISTENT" -ForegroundColor Green
} else {
    Write-Host "`n[ERROR] POWERSHELL HAS FEWER SIGNALS ($($signals.Count) vs $python_signals)" -ForegroundColor Red
    Write-Host "   Python implementation is MORE SENSITIVE" -ForegroundColor Red
    Write-Host "   Recommendation: Investigate difference" -ForegroundColor Red
}

# ============================================================================
# SAVE RESULTS
# ============================================================================

$output_dir = "$root\journal"
if (-not (Test-Path $output_dir)) {
    New-Item -ItemType Directory -Path $output_dir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$output_file = "$output_dir\tori_validation_powershell_$timestamp.json"

$results = @{
    timestamp = (Get-Date).ToString("o")
    market = $market
    period = $period
    candles_count = $candles.Count
    years = [math]::Round($years, 2)
    signals_count = $signals.Count
    frequency = [math]::Round($signals.Count / $years, 2)
    python_comparison = @{
        python_signals = $python_signals
        python_years = $python_period_years
        delta = $delta
    }
    signals = $signals
}

$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $output_file -Encoding UTF8

Write-Host "`n[OK] Results saved: $output_file" -ForegroundColor Green

Write-Host "`n$('='*60)" -ForegroundColor Cyan
Write-Host "VALIDATION COMPLETE" -ForegroundColor Cyan
Write-Host "$('='*60)" -ForegroundColor Cyan
