# lib_layer4_tori_timestop.ps1 -- Layer 4: stagnation time-stop + adaptive thresholds
# PS 5.1. UTF-8 BOM.
# Flag LAYER4_AUTO_EXECUTE: quando $true, Update-Layer4Review executa fechamento real na exchange.
# Default: $false (advisory only — envia alerta mas nao fecha).

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
    if ($HoursElapsed -ge $t.hard)   { return "HARD" }
    if ($HoursElapsed -ge $t.medium) { return "MEDIUM" }
    if ($HoursElapsed -ge $t.soft)   { return "SOFT" }
    return "NONE"
}

# ============================================================================
# Get-Layer4Decision - Retorna acao recomendada sem executar nada (advisory)
# ============================================================================
function Get-Layer4Decision {
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Position,
        [string]$Regime       = "SIDEWAYS",
        [string]$MentorAction = ""  # override: CLOSE_NOW, HOLD, HARVEST_PARTIAL
    )
    $entry      = [double]$Position.entry
    $peak       = [double]$Position.peak
    $current    = [double]$Position.currentPrice
    $target     = if ($Position.PSObject.Properties["target"])     { [double]$Position.target }     else { 0 }
    $resistance = if ($Position.PSObject.Properties["resistance"]) { [double]$Position.resistance } else { 0 }
    $openedAt   = [datetime]$Position.openedAt
    $hoursOpen  = ([datetime]::Now - $openedAt).TotalHours
    $peakProgress = if ($entry -gt 0) { ($peak - $entry) / $entry } else { 0 }

    # Mentor override: CLOSE_NOW → Layer 4 defere para Mentor
    if ($MentorAction -eq "CLOSE_NOW") {
        return [PSCustomObject]@{ action="DEFER_TO_MENTOR"; tier="NONE"; confidence=0.95; hoursOpen=[math]::Round($hoursOpen,1); peakProgress=[math]::Round($peakProgress,4); regime=$Regime; market=$Position.market }
    }

    # Detecta oportunidade de harvest: perto da resistência com lucro significativo
    $nearResistance = $resistance -gt 0 -and $current -gt 0 -and (($resistance - $current) / $current) -lt 0.03
    $profitPct = if ($entry -gt 0) { ($current - $entry) / $entry } else { 0 }
    if ($nearResistance -and $profitPct -gt 0.02 -and $MentorAction -ne "HOLD") {
        return [PSCustomObject]@{ action="HARVEST_PARTIAL"; harvestPct=0.40; confidence=0.85; tier="NONE"; hoursOpen=[math]::Round($hoursOpen,1); peakProgress=[math]::Round($peakProgress,4); regime=$Regime; market=$Position.market }
    }

    $tier = Classify-StagnationTier -HoursElapsed $hoursOpen -PeakProgress $peakProgress -Regime $Regime

    $action     = "HOLD"
    $confidence = 0.50
    switch ($tier) {
        "HARD"   { $action = "CLOSE_TIME_STOP";    $confidence = 0.90 }
        "MEDIUM" { $action = "REVIEW_STAGNATION";   $confidence = 0.60 }
        "SOFT"   { $action = "WARN_STAGNATION";     $confidence = 0.40 }
        default  {
            if ($profitPct -ge 0.15) { $action = "HARVEST"; $confidence = 0.70 }
            else                     { $action = "HOLD";     $confidence = 0.50 }
        }
    }

    return [PSCustomObject]@{
        action       = $action
        tier         = $tier
        confidence   = $confidence
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
