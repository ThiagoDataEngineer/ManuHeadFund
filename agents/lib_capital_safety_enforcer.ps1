# lib_capital_safety_enforcer.ps1 -- Capital Safety gates (fail-closed)
# Objetivo: Nenhuma trade pode bypassar limites de capital
#   - Max 1% account por trade
#   - R:R mínimo 1:5
#   - DD >= 10% reduz posição 50%
#   - DD >= 15% pausa daemons

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-CapitalSafetyCheck {
    param(
        [Parameter(Mandatory)] [double] $AccountBalanceUsd,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $StoplossPrice,
        [double] $TargetPrice = 0,
        [double] $ProposedSizeUsd = 0,
        [double] $BetaCap = 1.0,
        [string] $Market = "UNKNOWN",
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $checksPath = Join-Path $JournalDir "capital_safety_checks.jsonl"

    # Calcula risk por unit
    $riskPerUnit = [Math]::Abs($EntryPrice - $StoplossPrice)
    if ($riskPerUnit -eq 0) { $riskPerUnit = 0.01 }  # Avoid divide by zero

    # Calcula max position baseado em 1% capital
    $maxCapitalRisk = $AccountBalanceUsd * 0.01  # 1% = $50 de $5000
    $basePositionSize = $maxCapitalRisk / $riskPerUnit

    # Aplica beta cap (posição pode ser maior, mas cap em 1% capital)
    $betaAdjustedSize = $basePositionSize * $BetaCap
    $maxPositionUsd = $betaAdjustedSize * $EntryPrice

    # Nunca pode exceder 1% capital
    if ($maxPositionUsd -gt $maxCapitalRisk) {
        $maxPositionUsd = $maxCapitalRisk
    }

    # Verifica se posição proposta ultrapassa
    $passes = $true
    $reasons = @()

    if ($ProposedSizeUsd -gt 0 -and $ProposedSizeUsd -gt $maxPositionUsd) {
        $passes = $false
        $reasons += "Proposed size $ProposedSizeUsd exceeds 1% capital limit $maxPositionUsd"
    }

    # Valida R:R se targetPrice foi fornecido
    $rrRatio = 0
    if ($TargetPrice -gt 0) {
        $reward = [Math]::Abs($TargetPrice - $EntryPrice)
        if ($reward -gt 0 -and $riskPerUnit -gt 0) {
            $rrRatio = [Math]::Round($reward / $riskPerUnit, 2)
        }

        if ($rrRatio -lt 5) {
            $passes = $false
            $reasons += "R:R ratio $rrRatio < minimum 1:5"
        }
    }

    # Registra check em JSONL
    $checkEntry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        entry_price = $EntryPrice
        stoploss_price = $StoplossPrice
        target_price = $TargetPrice
        risk_per_unit = $riskPerUnit
        base_position_size = $basePositionSize
        beta_cap = $BetaCap
        max_position_usd = [Math]::Round($maxPositionUsd, 2)
        proposed_size_usd = $ProposedSizeUsd
        rr_ratio = $rrRatio
        passes = $passes
        reason = ($reasons -join " | ")
    } | ConvertTo-Json -Compress

    Add-Content -Path $checksPath -Value $checkEntry -Encoding UTF8

    return [PSCustomObject]@{
        passes = $passes
        reason = ($reasons -join " | ")
        max_position_usd = [Math]::Round($maxPositionUsd, 2)
        rr_ratio = $rrRatio
        account_balance = $AccountBalanceUsd
        capital_at_risk = [Math]::Round($maxCapitalRisk, 2)
        market = $Market
        checks_path = $checksPath
    }
}

function Get-DrawdownPercentage {
    param(
        [double] $StartingEquity,
        [double] $CurrentEquity
    )

    if ($StartingEquity -le 0) { return 0 }
    return [Math]::Round((($CurrentEquity - $StartingEquity) / $StartingEquity) * 100, 2)
}

function Test-DrawdownThreshold {
    param(
        [double] $CurrentDrawdownPct,
        [int] $ThresholdPct = 15
    )

    return $CurrentDrawdownPct -le (-1 * $ThresholdPct)
}
