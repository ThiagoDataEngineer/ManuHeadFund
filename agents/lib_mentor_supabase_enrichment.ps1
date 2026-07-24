# lib_mentor_supabase_enrichment.ps1
# Wire Supabase decision_grades_agg + mce_counterfactual_agg + trailing_positions
# Enriquecimento sofisticado do mentor com histórico real + contraFatual + performance
# 2026-07-09

$ErrorActionPreference = "Continue"

# Helper: ler estado Supabase (retorna JSON via REST API)
function Get-SupabaseState {
    [CmdletBinding()]
    param(
        [string]$Table = "decision_grades_agg",
        [hashtable]$Filter = @{}
    )

    $sbUrl = if ($env:SUPABASE_URL) { $env:SUPABASE_URL } else { "https://qpwvxhbbpvyqvqhvvdoe.supabase.co" }
    $sbKey = if ($env:SUPABASE_ANON_KEY) { $env:SUPABASE_ANON_KEY } else { "" }

    if (-not $sbKey) {
        Write-Host "[WARN] SUPABASE_ANON_KEY não configurada" -ForegroundColor Yellow
        return @()
    }

    $headers = @{
        "Authorization" = "Bearer $sbKey"
        "Content-Type" = "application/json"
        "Prefer" = "return=representation"
    }

    $query = "select=*"
    if ($Filter.Count -gt 0) {
        foreach ($k in $Filter.Keys) {
            $v = $Filter[$k]
            if ($k -eq "eq") {
                $query += "&$($v.key)=eq.$($v.value)"
            } elseif ($k -eq "gte") {
                $query += "&$($v.key)=gte.$($v.value)"
            }
        }
    }

    try {
        $resp = Invoke-RestMethod -Uri "$sbUrl/rest/v1/$Table?$query&limit=100" `
            -Method GET -Headers $headers -TimeoutSec 5 -ErrorAction Stop
        # 2026-07-23 FIX: "return @($resp)" com exatamente 1 registro vaza o
        # objeto cru pro pipeline de saida da funcao (PowerShell "desembrulha"
        # array-de-1-elemento quando o elemento em si e enumeravel/IDictionary
        # ou PSCustomObject) -- $capital[0] em Get-CapitalEnrichment quebrava
        # silenciosamente (Count virava o numero de PROPRIEDADES do objeto,
        # nao 1). "," (comma unario) forca o wrapper a sobreviver ao pipeline.
        return ,@($resp)
    } catch {
        Write-Host "[WARN] Get-SupabaseState $Table failed: $_" -ForegroundColor Yellow
        return ,@()
    }
}

# P0: Decision Grades Inversion
function Get-DecisionGradeEnrichment {
    [CmdletBinding()]
    param(
        [string]$Direction = "LONG",
        [string]$Regime = "BEAR_WEAK"
    )

    $grades = Get-SupabaseState -Table "decision_grades_agg"
    if (-not $grades) { return $null }

    # Procura grade que casa direction|regime
    $found = $grades | Where-Object {
        $_.direction -eq $Direction -and $_.regime -eq $Regime
    }

    if ($found) {
        return @{
            direction = $Direction
            regime = $Regime
            accuracy = [double]($found.accuracy -replace '%', '')
            n = [int]$found.n
            should_invert = ([double]($found.accuracy -replace '%', '') -lt 45 -and [int]$found.n -gt 30)
            would_win_pct = if ($found.would_win_pct) { [double]$found.would_win_pct } else { 0 }
            confidence = "HIGH"
        }
    }

    return $null
}

# P0: MCE Counterfactual (skipped gains)
function Get-CounterfactualEnrichment {
    [CmdletBinding()]
    param(
        [string]$Market = "LINKUSDT",
        [string]$Direction = "LONG"
    )

    $counterfactual = Get-SupabaseState -Table "mce_counterfactual_agg"
    if (-not $counterfactual) { return $null }

    $found = $counterfactual | Where-Object {
        $_.market -eq $Market -and $_.direction -eq $Direction
    }

    if ($found) {
        $n_win = [int]$found.n_would_win
        $n_skip = [int]$found.n_skipped

        if ($n_skip -gt 0) {
            $winRate = [math]::Round($n_win / $n_skip, 3)
            return @{
                market = $Market
                direction = $Direction
                avg_gain_pct = [double]$found.avg_gain_pct
                n_skipped = $n_skip
                n_would_win = $n_win
                win_rate = $winRate
                should_reconsider = ($winRate -gt 0.5)
                confidence = if ($n_skip -ge 10) { "HIGH" } else { "MEDIUM" }
            }
        }
    }

    return $null
}

# P1: Trailing Positions Historical Performance
function Get-TrailingHistoryEnrichment {
    [CmdletBinding()]
    param(
        [string]$Market = "ETHUSDT",
        [string]$Regime = "BULL_WEAK",
        [string]$Side = "LONG"
    )

    $trailing = Get-SupabaseState -Table "trailing_positions"
    if (-not $trailing) { return $null }

    $records = $trailing | Where-Object {
        $_.market -eq $Market -and $_.regime -eq $Regime -and $_.side -eq $Side
    }

    if ($records -and $records.Count -gt 0) {
        $avgProfit = ($records | Measure-Object -Property profit_realized_pct -Average).Average
        $avgSL = ($records | Measure-Object -Property sl_effectiveness -Average).Average
        $avgDuration = ($records | Measure-Object -Property duration_minutes -Average).Average

        return @{
            market = $Market
            regime = $Regime
            side = $Side
            n_trades = $records.Count
            avg_profit_pct = [math]::Round($avgProfit, 2)
            avg_sl_effectiveness = [math]::Round($avgSL, 3)
            avg_duration_min = [math]::Round($avgDuration, 0)
            confidence = if ($records.Count -ge 5) { "HIGH" } else { "MEDIUM" }
        }
    }

    return $null
}

# P1: Capital Context (sizing + margin check)
function Get-CapitalEnrichment {
    [CmdletBinding()]
    param()

    $capital = Get-SupabaseState -Table "capital_context"
    if (-not $capital -or $capital.Count -eq 0) { return $null }

    $latest = $capital[0]
    $marginPct = if ($latest.margin_free_pct) { [double]$latest.margin_free_pct } else { 0.15 }
    $deployedPct = if ($latest.deployed_pct) { [double]$latest.deployed_pct } else { 0.5 }
    $liqPrice = if ($latest.liquidation_price) { [double]$latest.liquidation_price } else { 0 }

    return @{
        balance_spot = if ($latest.balance_spot) { [double]$latest.balance_spot } else { 0 }
        balance_futures = if ($latest.balance_futures) { [double]$latest.balance_futures } else { 0 }
        deployed_pct = $deployedPct
        margin_free_pct = $marginPct
        sizing_reduction = if ($marginPct -lt 0.10) { 0.5 } else { 1.0 }
        risk_level = if ($marginPct -lt 0.05) { "CRITICAL" } elseif ($marginPct -lt 0.10) { "HIGH" } else { "NORMAL" }
        liq_price = $liqPrice
    }
}

# P1: Open Positions (duplicate check)
function Get-OpenPositionsConflict {
    [CmdletBinding()]
    param(
        [string]$Market = "LINKUSDT",
        [string]$Direction = "SHORT"
    )

    $positions = Get-SupabaseState -Table "open_positions"
    if (-not $positions) { return $null }

    $existing = $positions | Where-Object { $_.market -eq $Market }
    if ($existing) {
        $existingDir = $existing.side
        if ($existingDir -ne $Direction) {
            return @{
                market = $Market
                proposed_direction = $Direction
                existing_direction = $existingDir
                conflict = $true
                reason = "Position já aberta em direção oposta"
            }
        }
    }

    return @{ conflict = $false }
}

# MAIN: Monta enriquecimento completo
function Get-MentorSupabaseEnrichment {
    [CmdletBinding()]
    param(
        [string]$Market = "LINKUSDT",
        [string]$Direction = "LONG",
        [string]$Regime = "BEAR_WEAK",
        [double]$ProposedSize = 100
    )

    $enrichment = @{
        timestamp = Get-Date -Format 'o'
        market = $Market
        direction = $Direction
        regime = $Regime
        proposed_size_usd = $ProposedSize
    }

    # P0: Decision Grades
    $grades = Get-DecisionGradeEnrichment -Direction $Direction -Regime $Regime
    if ($grades) {
        $enrichment.decision_grades = $grades
        if ($grades.should_invert) {
            $enrichment.decision_invert = $true
            $enrichment.invert_reason = "Grade accuracy $($grades.accuracy)% < 45% threshold"
        }
    }

    # P0: Counterfactual
    $cfactual = Get-CounterfactualEnrichment -Market $Market -Direction $Direction
    if ($cfactual) {
        $enrichment.counterfactual = $cfactual
        if ($cfactual.should_reconsider) {
            $enrichment.should_reconsider_skipped = $true
            $enrichment.reconsider_reason = "Win rate $($cfactual.win_rate * 100)% > 50% on skipped opportunities"
        }
    }

    # P1: Trailing History
    $trailing = Get-TrailingHistoryEnrichment -Market $Market -Regime $Regime -Side $Direction
    if ($trailing) {
        $enrichment.market_history = $trailing
    }

    # P1: Capital
    $capital = Get-CapitalEnrichment
    if ($capital) {
        $enrichment.capital = $capital
        if ($capital.sizing_reduction -lt 1.0) {
            $enrichment.sizing_reduced_to = [math]::Round($ProposedSize * $capital.sizing_reduction, 2)
        }
    }

    # P1: Position conflicts
    $conflict = Get-OpenPositionsConflict -Market $Market -Direction $Direction
    if ($conflict -and $conflict.conflict) {
        $enrichment.position_conflict = $conflict
    }

    return $enrichment
}

# Helper: Formata enriquecimento pra incluir no prompt
function Format-EnrichmentPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Enrichment
    )

    $lines = @(
        "[SUPABASE ENRICHMENT]"
    )

    # Decision Grades
    if ($Enrichment.decision_grades) {
        $grades = $Enrichment.decision_grades
        $lines += "  📊 Decision Grades ($($grades.direction)|$($grades.regime)):"
        $lines += "     Accuracy: $($grades.accuracy)% (n=$($grades.n))"
        if ($Enrichment.decision_invert) {
            $lines += "     ⚠️  INVERT: $($Enrichment.invert_reason)"
        }
    }

    # Counterfactual
    if ($Enrichment.counterfactual) {
        $cf = $Enrichment.counterfactual
        $lines += "  🔄 Counterfactual Skipped:"
        $lines += "     Avg Gain: $($cf.avg_gain_pct)% ($($cf.n_would_win)/$($cf.n_skipped) would win)"
        if ($Enrichment.should_reconsider_skipped) {
            $lines += "     🔆 RECONSIDER: $($Enrichment.reconsider_reason)"
        }
    }

    # Market History
    if ($Enrichment.market_history) {
        $hist = $Enrichment.market_history
        $lines += "  📈 Market History ($($hist.side)|$($hist.regime)):"
        $lines += "     Avg Profit: $($hist.avg_profit_pct)% (n=$($hist.n_trades))"
        $lines += "     SL Effectiveness: $($hist.avg_sl_effectiveness)"
        $lines += "     Avg Duration: $($hist.avg_duration_min) min"
    }

    # Capital
    if ($Enrichment.capital) {
        $cap = $Enrichment.capital
        $lines += "  💰 Capital Status:"
        $lines += "     Deployed: $($cap.deployed_pct * 100)% | Margin Free: $($cap.margin_free_pct * 100)%"
        $lines += "     Risk Level: $($cap.risk_level)"
        if ($Enrichment.sizing_reduced_to) {
            $lines += "     ⚠️  Sizing reduced to \$$($Enrichment.sizing_reduced_to) (was \$$($Enrichment.proposed_size_usd))"
        }
    }

    # Conflicts
    if ($Enrichment.position_conflict -and $Enrichment.position_conflict.conflict) {
        $conflict = $Enrichment.position_conflict
        $lines += "  🚫 Position Conflict:"
        $lines += "     Market $($conflict.market) already has $($conflict.existing_direction) position"
        $lines += "     Cannot open $($conflict.proposed_direction) (reason: $($conflict.reason))"
    }

    return $lines -join "`n"
}

# Export disabled for dot-source compatibility (PS 5.1)
# Export-ModuleMember -Function @(
#     'Get-DecisionGradeEnrichment'
#     'Get-CounterfactualEnrichment'
#     'Get-TrailingHistoryEnrichment'
#     'Get-CapitalEnrichment'
#     'Get-OpenPositionsConflict'
#     'Get-MentorSupabaseEnrichment'
#     'Format-EnrichmentPrompt'
#     'Get-SupabaseState'
# )
