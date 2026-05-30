# fix_injusdt_trailing_stop.ps1
# Complete fix for INJUSDT: Enable trailing stop + partial exits + monitoring
# 2026-05-29

param(
    [Parameter(Mandatory=$false)] [switch]$DryRun = $false,
    [Parameter(Mandatory=$false)] [switch]$EnableMonitoring = $true
)

# Load all necessary libraries
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_order_validation.ps1
. agents/lib_position_protection.ps1
. agents/lib_trailing_stop_intelligent.ps1

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch($Status) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Cyan" }
        default { "White" }
    }
    Write-Host "[$Status] $Message" -ForegroundColor $color
}

Write-Host ""
Write-Host "INJUSDT TRAILING STOP + PARTIAL EXITS FIX" -ForegroundColor Cyan
Write-Host "2026-05-29 Complete Fix" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 1: Audit Current Position
# ============================================================================

Write-Status "STEP 1: Auditing current INJUSDT position..." "INFO"
Write-Host ""

try {
    $positions = CoinEx-GetPendingPositions -Market "INJUSDT"
    if (-not $positions) {
        Write-Status "No INJUSDT position found" "ERROR"
        exit 1
    }
    
    $pos = @($positions)[0]
    $entry = [double]$pos.avg_entry_price
    $qty = [double]$pos.amount
    $currentPrice = [double]$pos.settle_price
    $currentSL = [double]$pos.stop_loss_price
    $currentTP = [double]$pos.take_profit_price
    $trailingStop = $pos.trailing_stop_price
    
    Write-Status "Position found successfully" "SUCCESS"
    Write-Host ""
    Write-Host "Current Position State:" -ForegroundColor Yellow
    Write-Host "  Entry Price:        $entry"
    Write-Host "  Current Price:      $currentPrice"
    Write-Host "  Amount:             $qty INJ"
    Write-Host "  Side:               $($pos.side)"
    Write-Host "  Stop Loss:          $currentSL" -ForegroundColor Green
    Write-Host "  Take Profit:        $currentTP" -ForegroundColor Green
    if ($trailingStop) {
        Write-Host "  Trailing Stop:      $trailingStop" -ForegroundColor Green
    } else {
        Write-Host "  Trailing Stop:      NOT SET" -ForegroundColor Red
    }
    Write-Host ""
    
} catch {
    Write-Status "Error getting position: $_" "ERROR"
    exit 1
}

# ============================================================================
# STEP 2: Calculate Optimal Values
# ============================================================================

Write-Status "STEP 2: Calculating optimal TP/SL and trailing stop..." "INFO"
Write-Host ""

$peak24h = 6.7004
$tpsl = Initialize-AutomaticTPSL -Entry $entry -CurrentPrice $currentPrice -Peak24h $peak24h -Qty $qty

Write-Host "Calculated Values:" -ForegroundColor Yellow
Write-Host "  TP Base:            $($tpsl.TPBase)"
Write-Host "  SL Base:            $($tpsl.SLBase)"
Write-Host "  Trailing Stop:      $($tpsl.TrailingStop) (14.5 percent below peak)"
Write-Host "  Trailing Percent:   $($tpsl.TrailingPercent) percent"
Write-Host ""

Write-Host "Partial Exit Levels:" -ForegroundColor Yellow
foreach ($exit in $tpsl.PartialExits) {
    Write-Host "  Level $($exit.Level): Price=$($exit.Price), Qty=$($exit.Qty) INJ, $($exit.Percent) percent"
}
Write-Host ""

# ============================================================================
# STEP 3: Validate Current Protection
# ============================================================================

Write-Status "STEP 3: Validating current protection..." "INFO"
Write-Host ""

$hasSL = $currentSL -and $currentSL -ne '--' -and $currentSL -ne '0'
$hasTP = $currentTP -and $currentTP -ne '--' -and $currentTP -ne '0'
$hasTrailing = $trailingStop -and $trailingStop -ne '--' -and $trailingStop -ne '0'

Write-Host "Protection Status:" -ForegroundColor Yellow
if ($hasSL) {
    Write-Host "  Has Stop Loss:      YES"
} else {
    Write-Host "  Has Stop Loss:      NO"
}
if ($hasTP) {
    Write-Host "  Has Take Profit:    YES"
} else {
    Write-Host "  Has Take Profit:    NO"
}
if ($hasTrailing) {
    Write-Host "  Has Trailing Stop:  YES"
} else {
    Write-Host "  Has Trailing Stop:  NO"
}
Write-Host ""

if (-not $hasSL -or -not $hasTP) {
    Write-Status "Position is UNPROTECTED - needs immediate repair!" "ERROR"
} elseif (-not $hasTrailing) {
    Write-Status "Position is protected but MISSING TRAILING STOP" "WARNING"
} else {
    Write-Status "Position is fully protected" "SUCCESS"
}
Write-Host ""

# ============================================================================
# STEP 4: Apply Fixes (if not dry-run)
# ============================================================================

if ($DryRun) {
    Write-Status "DRY RUN MODE - No changes will be applied" "WARNING"
    Write-Host ""
} else {
    Write-Status "STEP 4: Applying fixes..." "INFO"
    Write-Host ""
    
    # Fix 1: Ensure SL is set
    if (-not $hasSL) {
        Write-Status "Applying Stop Loss: $($tpsl.SLBase)..." "INFO"
        try {
            $slResult = Set-PositionProtection -Market "INJUSDT" -StopLoss $tpsl.SLBase -TakeProfit 0
            if ($slResult.success) {
                Write-Status "Stop Loss applied successfully" "SUCCESS"
            } else {
                Write-Status "Failed to apply Stop Loss: $($slResult.reason)" "ERROR"
            }
        } catch {
            Write-Status "Error applying Stop Loss: $_" "ERROR"
        }
    } else {
        Write-Status "Stop Loss already set at $currentSL" "SUCCESS"
    }
    
    # Fix 2: Ensure TP is set
    if (-not $hasTP) {
        Write-Status "Applying Take Profit: $($tpsl.TPBase)..." "INFO"
        try {
            $tpResult = Set-PositionProtection -Market "INJUSDT" -StopLoss 0 -TakeProfit $tpsl.TPBase
            if ($tpResult.success) {
                Write-Status "Take Profit applied successfully" "SUCCESS"
            } else {
                Write-Status "Failed to apply Take Profit: $($tpResult.reason)" "ERROR"
            }
        } catch {
            Write-Status "Error applying Take Profit: $_" "ERROR"
        }
    } else {
        Write-Status "Take Profit already set at $currentTP" "SUCCESS"
    }
    
    # Fix 3: Enable Trailing Stop
    if (-not $hasTrailing) {
        Write-Status "Enabling Trailing Stop at $($tpsl.TrailingStop)..." "INFO"
        try {
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $resp = CoinEx-Post "/v2/futures/set-position-stop-loss" @{
                market            = "INJUSDT"
                market_type       = "FUTURES"
                stop_loss_type    = "mark_price"
                stop_loss_price   = ([math]::Round($tpsl.TrailingStop, 4)).ToString($inv)
            }
            
            if ($resp.code -eq 0) {
                Write-Status "Trailing Stop enabled successfully" "SUCCESS"
            } else {
                Write-Status "Failed to enable Trailing Stop: $($resp.message)" "ERROR"
            }
        } catch {
            Write-Status "Error enabling Trailing Stop: $_" "ERROR"
        }
    } else {
        Write-Status "Trailing Stop already enabled at $trailingStop" "SUCCESS"
    }
    
    Write-Host ""
}

# ============================================================================
# STEP 5: Create Monitoring Configuration
# ============================================================================

Write-Status "STEP 5: Creating monitoring configuration..." "INFO"
Write-Host ""

$monitorConfig = @{
    Market = "INJUSDT"
    Entry = $entry
    Qty = $qty
    Peak24h = $peak24h
    StopLoss = $currentSL
    TakeProfit = $currentTP
    TrailingStop = $tpsl.TrailingStop
    TrailingPercent = $tpsl.TrailingPercent
    PartialExits = $tpsl.PartialExits
    CreatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    UpdatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

$configPath = "memory/injusdt_trailing_config_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$monitorConfig | ConvertTo-Json | Out-File -FilePath $configPath -Encoding UTF8

Write-Status "Monitoring config saved to: $configPath" "SUCCESS"
Write-Host ""

# ============================================================================
# STEP 6: Summary and Recommendations
# ============================================================================

Write-Host ""
Write-Host "SUMMARY & NEXT STEPS" -ForegroundColor Green
Write-Host ""

Write-Host "Current INJUSDT Protection:" -ForegroundColor Yellow
Write-Host "  Stop Loss:       $currentSL"
Write-Host "  Take Profit:     $currentTP"
if ($hasTrailing) {
    Write-Host "  Trailing Stop:   $trailingStop"
} else {
    Write-Host "  Trailing Stop:   NEEDS TO BE SET"
}
Write-Host ""

Write-Host "Recommended Actions:" -ForegroundColor Cyan
Write-Host "  1. Monitor position in real-time:"
Write-Host "     powershell -File scripts/trailing_stop_monitor.ps1"
Write-Host ""
Write-Host "  2. Enable automatic partial exits:"
Write-Host "     powershell -File scripts/enable_partial_exits.ps1"
Write-Host ""
Write-Host "  3. Set up alerts:"
Write-Host "     powershell -File scripts/setup_alerts.ps1"
Write-Host ""

Write-Host "Documentation:" -ForegroundColor Cyan
Write-Host "  - INJUSDT_TRAILING_STOP_FIX_20260529.md"
Write-Host "  - QUICK_REFERENCE.md"
Write-Host "  - COMO_USAR_AGORA.md"
Write-Host ""

Write-Status "Fix script completed successfully" "SUCCESS"
Write-Host ""
