# lib_layer4_tori_timestop.ps1 -- Layer 4: stagnation time-stop + adaptive thresholds
# PS 5.1. UTF-8 BOM.

# ============================================================================
# Get-StagnationThresholds - Thresholds de horas por regime (SOFT/MEDIUM/HARD)
# ============================================================================
function Get-StagnationThresholds {
    param([string]$Regime = "SIDEWAYS")
    $map = @{
        "BULL_STRONG"    = @{ soft=8;  medium=12; hard=18 }
        "BULL_WEAK"      = @{ soft=12; medium=18; hard=24 }
        "TRANSITION_UP"  = @{ soft=14; medium=20; hard=30 }
        "SIDEWAYS"       = @{ soft=18; medium=24; hard=36 }
        "TRANSITION_DOWN"= @{ soft=12; medium=18; hard=24 }
        "BEAR_WEAK"      = @{ soft=8;  medium=12; hard=18 }
        "BEAR_STRONG"    = @{ soft=4;  medium=8;  hard=12 }
        "CAPITULATION"   = @{ soft=2;  medium=4;  hard=6  }
    }
    $t = $map[$Regime]
    if (-not $t) { $t = $map["SIDEWAYS"] }
    return [PSCustomObject]@{ soft=$t.soft; medium=$t.medium; hard=$t.hard }
}

# ============================================================================
# Classify-StagnationTier - Classifica tier com base em horas + progresso
# ============================================================================
function Classify-StagnationTier {
    param(
        [double]$HoursElapsed,
        [double]$PeakProgress,   # (peak - entry) / entry; >= 0.005 = nao estagnado
        [string]$Regime = "SIDEWAYS"
    )
    # Se teve progresso real (>= 0.5% do entry), nao conta como estagnado
    if ($PeakProgress -ge 0.005) { return "NONE" }

    $t = Get-StagnationThresholds -Regime $Regime
    if ($HoursElapsed -gt $t.hard)   { return "HARD" }
    if ($HoursElapsed -gt $t.medium) { return "MEDIUM" }
    if ($HoursElapsed -gt $t.soft)   { return "SOFT" }
    return "NONE"
}

# ============================================================================
# Get-Layer4Decision - Retorna acao recomendada sem executar nada (advisory)
# ============================================================================
function Get-Layer4Decision {
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Position,
        [string]$Regime = "SIDEWAYS"
    )
    $entry       = [double]$Position.entry
    $peak        = [double]$Position.peak
    $current     = [double]$Position.currentPrice
    $openedAt    = [datetime]$Position.openedAt
    $hoursOpen   = ([datetime]::Now - $openedAt).TotalHours
    $peakProgress = if ($entry -gt 0) { ($peak - $entry) / $entry } else { 0 }

    $tier = Classify-StagnationTier -HoursElapsed $hoursOpen -PeakProgress $peakProgress -Regime $Regime

    $action = switch ($tier) {
        "HARD"   { "CLOSE_TIME_STOP" }
        "MEDIUM" { "REVIEW_STAGNATION" }
        "SOFT"   { "WARN_STAGNATION" }
        default  {
            # Mesmo sem estagnacao, checar se esta em lucro para harvest
            $profitPct = if ($entry -gt 0) { ($current - $entry) / $entry } else { 0 }
            if ($profitPct -ge 0.15) { "HARVEST" } else { "HOLD" }
        }
    }

    return [PSCustomObject]@{
        action       = $action
        tier         = $tier
        hoursOpen    = [math]::Round($hoursOpen, 1)
        peakProgress = [math]::Round($peakProgress, 4)
        regime       = $Regime
        market       = $Position.market
    }
}

# ============================================================================
# Update-Layer4Review - Processa lista de posicoes, retorna decisoes
# ============================================================================
function Update-Layer4Review {
    param(
        [PSCustomObject[]]$Positions = @(),
        [switch]$AutoExecute
    )
    $decisions = @()
    foreach ($pos in $Positions) {
        $regime = if ($pos.regime) { $pos.regime } else { "SIDEWAYS" }
        $d = Get-Layer4Decision -Position $pos -Regime $regime
        $d | Add-Member -NotePropertyName autoExecute -NotePropertyValue ($AutoExecute.IsPresent) -Force

        if ($AutoExecute -and $d.action -eq "CLOSE_TIME_STOP") {
            if (Get-Command CoinEx-ClosePosition -ErrorAction SilentlyContinue) {
                try {
                    CoinEx-ClosePosition -market $pos.market | Out-Null
                    $d | Add-Member -NotePropertyName executed -NotePropertyValue $true -Force
                } catch {
                    $d | Add-Member -NotePropertyName executed -NotePropertyValue $false -Force
                }
            }
        }
        $decisions += $d
    }
    return $decisions
}
