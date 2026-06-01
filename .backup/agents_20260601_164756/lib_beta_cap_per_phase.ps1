# lib_beta_cap_per_phase.ps1 -- Dynamic beta cap per market phase.
#
# Tier 1 T-Beta (2026-05-23): Phase 2 A/B revelou bands beta>1.2 com EV positivo.
# Per-phase analise mostrou:
#   - h24_p1_bull: cap 1.6 (EV +21.6% em 1.4-1.6)
#   - h24_p2_top: cap 1.2 (sample ruim, conservador)
#   - h24_p3_bear: cap 1.4 (1.0-1.2 peak mas 1.4 ainda +6.6%)
#   - h24_p4_rec: cap 1.2 default (insufficient)
#
# Funcoes:
#   - Get-BetaCapForPhase: lookup cap per phase
#   - Test-BetaWithinCap: validate asset/portfolio beta vs phase cap
#
# Backward compat: defaults caso phase desconhecida = 1.2 (atual).
# Wire opt-in: callers passam phase, lib retorna cap dinamico.
#
# PS 5.1. UTF-8 BOM.


# Per-phase cap table (data-driven from Phase 2 A/B per-phase analysis)
$script:BETA_CAP_PER_PHASE = @{
    "h24_p1_bull"  = @{ warn = 1.3; block = 1.6; rationale = "bull amplifies gains; EV +21.6% em 1.4-1.6" }
    "h24_p2_top"   = @{ warn = 1.0; block = 1.2; rationale = "top phase mixed signals; stay conservador" }
    "h24_p3_bear"  = @{ warn = 1.1; block = 1.4; rationale = "bear sweet 1.0-1.2 mas 1.4 ainda +6.6% EV" }
    "h24_p4_rec"   = @{ warn = 1.0; block = 1.2; rationale = "recovery insufficient data; conservador default" }
    "h20_p1_bull"  = @{ warn = 1.3; block = 1.6; rationale = "bull pattern same as h24" }
    "h20_p2_top"   = @{ warn = 1.0; block = 1.2; rationale = "top same as h24" }
    "h20_p3_bear"  = @{ warn = 1.1; block = 1.4; rationale = "bear same as h24" }
    "h20_p4_rec"   = @{ warn = 1.0; block = 1.2; rationale = "recovery conservador" }
}

# Default fallback (caso phase desconhecida) — current production cap
$script:BETA_CAP_DEFAULT = @{ warn = 1.0; block = 1.2; rationale = "default conservador (atual prod)" }


# 2026-05-23 fix wire mismatch: regime_state.json usa nomes SEMANTICOS (BEAR_WEAK,
# BULL_STRONG, etc) mas table key eh PHASE_HALVING (h24_p3_bear). Translator mapeia
# regime semantic -> phase halving usando data atual (months post halving 2024-04-19).
function _Get-PhaseFromHalvingMonths {
    $halving2024 = [datetime]::new(2024, 4, 19, 0, 0, 0, [DateTimeKind]::Utc)
    $halving2020 = [datetime]::new(2020, 5, 11, 0, 0, 0, [DateTimeKind]::Utc)
    $halving2028 = [datetime]::new(2028, 4, 15, 0, 0, 0, [DateTimeKind]::Utc)
    $now = (Get-Date).ToUniversalTime()
    if ($now -ge $halving2028) {
        $mph = ($now - $halving2028).TotalDays / 30.5
        $prefix = "h28"
    } elseif ($now -ge $halving2024) {
        $mph = ($now - $halving2024).TotalDays / 30.5
        $prefix = "h24"
    } elseif ($now -ge $halving2020) {
        $mph = ($now - $halving2020).TotalDays / 30.5
        $prefix = "h20"
    } else { return "pre_h20" }

    if ($mph -lt 6)       { return "${prefix}_p1_bull" }
    elseif ($mph -lt 12)  { return "${prefix}_p2_top" }
    elseif ($mph -lt 30)  { return "${prefix}_p3_bear" }
    else                  { return "${prefix}_p4_rec" }
}

function _Translate-RegimeToPhase {
    # Mapeia regime semantic (BULL_WEAK, BEAR_STRONG, etc) -> phase halving (h24_p3_bear).
    # Usa data atual pra detectar cycle/phase. Strings desconhecidas retornam vazio
    # (caller usa default fallback).
    param([string] $RegimeOrPhase)
    if (-not $RegimeOrPhase) { return "" }
    # If already phase format (h20_/h24_/h28_/pre_h20), return as-is
    if ($RegimeOrPhase -match '^(h20_p|h24_p|h28_p|pre_h20)') { return $RegimeOrPhase }
    # Regime semantic conhecido? Translate via data atual
    $regimeKnown = @('BULL_STRONG','BULL_WEAK','BEAR_STRONG','BEAR_WEAK',
                     'TRANSITION_UP','TRANSITION_DOWN','CAPITULATION',
                     'STRUCTURAL_BREAK','SIDEWAYS','RECOVERY','TOP','UNKNOWN')
    if ($regimeKnown -contains $RegimeOrPhase.ToUpper()) {
        return (_Get-PhaseFromHalvingMonths)
    }
    # Unknown string: return empty (fall through to default cap)
    return ""
}


function Get-BetaCapForPhase {
    <#
    .SYNOPSIS
    Returns @{warn, block, rationale, phase, source} dado phase OR regime semantic.

    .PARAMETER Phase
    Aceita ambos:
      - Phase halving: "h24_p3_bear" (table key direto)
      - Regime semantic: "BEAR_WEAK", "BULL_STRONG" (translates to phase via current date)
    Vazio/unknown -> default.

    .EXAMPLE
    $cap = Get-BetaCapForPhase -Phase "BEAR_WEAK"   # translates to h24_p3_bear (current)
    if ($asset_beta -gt $cap.block) { "BLOCK" }
    #>
    [CmdletBinding()]
    param([string] $Phase = "")

    # Translator: aceita regime semantic ou phase direto
    $effectivePhase = _Translate-RegimeToPhase -RegimeOrPhase $Phase

    if (-not $effectivePhase -or -not $script:BETA_CAP_PER_PHASE.ContainsKey($effectivePhase)) {
        $d = $script:BETA_CAP_DEFAULT
        return [PSCustomObject]@{
            warn = [double]$d.warn
            block = [double]$d.block
            rationale = $d.rationale
            phase = if ($effectivePhase) { $effectivePhase } else { "unknown" }
            input_regime = $Phase
            source = "default"
        }
    }
    $c = $script:BETA_CAP_PER_PHASE[$effectivePhase]
    return [PSCustomObject]@{
        warn = [double]$c.warn
        block = [double]$c.block
        rationale = $c.rationale
        phase = $effectivePhase
        input_regime = $Phase
        source = "per_phase_table"
    }
}


function Test-BetaWithinCap {
    <#
    .SYNOPSIS
    Tests asset OR portfolio beta against phase cap. Returns level (OK|WARN|BLOCK) + reason.

    .PARAMETER Beta
    Asset OR portfolio_after_add beta value.

    .PARAMETER Phase
    Current phase (ex: "h24_p3_bear").

    .PARAMETER Strict
    If $true, treats WARN as BLOCK (conservadora).

    .OUTPUTS
    PSCustomObject @{ level (OK|WARN|BLOCK), beta, cap_warn, cap_block, phase, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $Beta,
        [string] $Phase = "",
        [switch] $Strict
    )
    $cap = Get-BetaCapForPhase -Phase $Phase
    $level = "OK"
    if ($Beta -gt $cap.block) { $level = "BLOCK" }
    elseif ($Beta -gt $cap.warn) { $level = "WARN" }
    if ($Strict -and $level -eq "WARN") { $level = "BLOCK" }

    $reason = switch ($level) {
        "OK"    { "beta=$Beta within cap warn=$($cap.warn) block=$($cap.block) phase=$($cap.phase)" }
        "WARN"  { "beta=$Beta above warn=$($cap.warn) for phase=$($cap.phase) ($($cap.rationale))" }
        "BLOCK" { "beta=$Beta above block=$($cap.block) for phase=$($cap.phase) ($($cap.rationale))" }
    }

    return [PSCustomObject]@{
        level = $level
        beta = $Beta
        cap_warn = $cap.warn
        cap_block = $cap.block
        phase = $cap.phase
        source = $cap.source
        rationale = $cap.rationale
        reason = $reason
    }
}


function Get-AllPhaseCaps {
    <#
    .SYNOPSIS
    Returns full table per-phase pra audit/doc.
    #>
    [CmdletBinding()] param()
    $out = @()
    foreach ($phase in $script:BETA_CAP_PER_PHASE.Keys) {
        $c = $script:BETA_CAP_PER_PHASE[$phase]
        $out += [PSCustomObject]@{
            phase = $phase
            warn = [double]$c.warn
            block = [double]$c.block
            rationale = $c.rationale
        }
    }
    return @($out | Sort-Object phase)
}
