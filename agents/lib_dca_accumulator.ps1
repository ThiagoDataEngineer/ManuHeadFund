# lib_dca_accumulator.ps1 — DCA acumulação automática em fundo halving
# Compra BTC+ETH dia a dia quando BTC está em downtrend ou fundo histórico
# PS 5.1. UTF-8 BOM.

function Get-DcaState {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $JournalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $stateFile = Join-Path $journalDir "dca_state.json"

    if (-not (Test-Path $stateFile)) {
        return @{ accumulated_usd=0.0; positions=@(); last_buy=(Get-Date).AddDays(-1) }
    }

    try {
        Get-Content $stateFile -Raw | ConvertFrom-Json
    } catch {
        return @{ accumulated_usd=0.0; positions=@(); last_buy=(Get-Date).AddDays(-1) }
    }
}

function Save-DcaState {
    param(
        [double]$AccumulatedUsd,
        [object[]]$Positions,
        [datetime]$LastBuy,
        [string]$JournalDir = $global:JOURNAL_DIR
    )

    $journalDir = if ($JournalDir) { $JournalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    if (-not (Test-Path $journalDir)) { mkdir $journalDir | Out-Null }

    $state = @{
        accumulated_usd = $AccumulatedUsd
        positions = $Positions
        last_buy = $LastBuy.ToString("o")
        updated_at = (Get-Date).ToString("o")
    }

    $state | ConvertTo-Json -AsArray | Set-Content (Join-Path $journalDir "dca_state.json") -Encoding UTF8
}

function Test-DcaShouldBuy {
    param(
        [double]$BtcPrice,
        [double]$BtcHistoricalLow = 40000,
        [double]$BtcHistoricalHigh = 65000,
        [double]$DowntrendThreshold = 0.20
    )

    # Compra se BTC está baixo (estratégia acumular)
    $bottomRange = $BtcHistoricalLow * 1.10
    $downTrendLevel = $BtcHistoricalHigh * (1.0 - $DowntrendThreshold)

    return (($BtcPrice -lt $bottomRange) -or ($BtcPrice -lt $downTrendLevel))
}

function Get-DcaAllocationPercentage {
    param(
        [string]$HalvingPhase = "phase_1_bull",
        [double]$MacroBias = 50
    )

    # Allocation % do capital disponível por halving phase
    $alloc = @{
        "pre_halving"      = 0.02    # 2% daily (agressivo acumular antes)
        "phase_1_bull"     = 0.01    # 1% daily (bull, mas ainda acumula)
        "phase_2_top"      = 0.005   # 0.5% (topo, pausa)
        "phase_3_bear"     = 0.03    # 3% (bear, agressivo)
        "phase_4_recovery" = 0.015   # 1.5% (recovery)
    }

    $base = if ($alloc.ContainsKey($HalvingPhase)) { $alloc[$HalvingPhase] } else { 0.01 }

    # Macro bias 0-30 = muito pessimista, dobra alocação
    if ($MacroBias -lt 30) { $base = $base * 2 }
    # Macro bias 70+ = otimista demais, metade
    if ($MacroBias -gt 70) { $base = $base * 0.5 }

    return [math]::Round([double]$base, 4)
}

function Invoke-DcaBuy {
    param(
        [double]$AvailableCapital,
        [double]$DcaPctAllocation,
        [string]$Market = "BTCUSDT",  # ou ETHUSDT
        [double]$Price,
        [string]$JournalDir = $global:JOURNAL_DIR
    )

    $buyUsd = $AvailableCapital * $DcaPctAllocation
    if ($buyUsd -lt 10) { return @{ executed=$false; reason="buy_size_too_small" } }

    $qty = [math]::Round($buyUsd / $Price, 8)

    # Log purchase
    $journalDir = if ($JournalDir) { $JournalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $logFile = Join-Path $journalDir "dca_purchases.jsonl"

    $purchase = @{
        timestamp = (Get-Date).ToString("o")
        market = $Market
        qty = $qty
        price = $Price
        usd_amount = $buyUsd
        halving_phase = "unknown"  # set by caller if available
    } | ConvertTo-Json -Compress

    Add-Content -Path $logFile -Value $purchase -Encoding UTF8 -ErrorAction SilentlyContinue

    return @{
        executed = $true
        market = $Market
        qty = $qty
        price = $Price
        usd = $buyUsd
    }
}

function Get-DcaStatistics {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $logFile = Join-Path $journalDir "dca_purchases.jsonl"

    if (-not (Test-Path $logFile)) {
        return @{ total_purchases=0; total_usd_invested=0.0; avg_price=0.0; current_value_usd=0.0 }
    }

    $purchases = @()
    Get-Content $logFile | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try { $purchases += (ConvertFrom-Json $_) } catch { }
    }

    $totalUsd = ($purchases | Measure-Object -Property usd_amount -Sum).Sum
    $totalQty = ($purchases | Measure-Object -Property qty -Sum).Sum
    $avgPrice = if ($totalQty -gt 0) { $totalUsd / $totalQty } else { 0 }

    return @{
        total_purchases = $purchases.Count
        total_usd_invested = [math]::Round($totalUsd, 2)
        total_qty = [math]::Round($totalQty, 8)
        avg_price = [math]::Round($avgPrice, 2)
        purchases = $purchases
    }
}
