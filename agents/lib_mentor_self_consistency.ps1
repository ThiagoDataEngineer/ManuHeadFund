# lib_mentor_self_consistency.ps1 -- C.8 wire 2026-05-26
# Critical decisions (STRONG_EXECUTAR amplifier 1.5x sizing / HARD_VETO blacklist 24h)
# devem ter 2 LLM calls concordando. Divergencia = downgrade pra REVISAR (paper-only).
# Anti-overconfidence: forca consenso onde stakes maiores.
#
# Cost-aware: so dispara 2x call quando 1a foi STRONG_EXECUTAR ou HARD_VETO
# (~5-10% das decisoes empirico). EXECUTAR/ABORTAR continuam 1x.

$script:CRITICAL_TIERS = @("STRONG_EXECUTAR","HARD_VETO")

function Test-MentorCriticalTier {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Veredicto5tier)
    return ($script:CRITICAL_TIERS -contains $Veredicto5tier)
}

function Test-SelfConsistencyRequired {
    # Alias semantico mais claro pro caller (chama 2x call so se TRUE)
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)] [string] $Veredicto5tier)
    return Test-MentorCriticalTier -Veredicto5tier $Veredicto5tier
}

function Resolve-SelfConsistency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $First,
        [Parameter(Mandatory)] [PSCustomObject] $Second
    )

    $t1 = [string]$First.veredicto_5tier
    $t2 = [string]$Second.veredicto_5tier

    if ($t1 -eq $t2) {
        return [PSCustomObject]@{
            final = $First
            consistent = $true
            reason = "agreement on $t1"
        }
    }

    # Side classification
    $bullish = @("STRONG_EXECUTAR","EXECUTAR")
    $bearish = @("ABORTAR","HARD_VETO")
    $neutral = @("REVISAR")

    $s1 = if ($t1 -in $bullish) { "bull" } elseif ($t1 -in $bearish) { "bear" } else { "neutral" }
    $s2 = if ($t2 -in $bullish) { "bull" } elseif ($t2 -in $bearish) { "bear" } else { "neutral" }

    # Opposite sides (bull x bear) -> REVISAR (max safe)
    if (($s1 -eq "bull" -and $s2 -eq "bear") -or ($s1 -eq "bear" -and $s2 -eq "bull")) {
        $final = [PSCustomObject]@{
            decision = "VETAR"
            veredicto_5tier = "REVISAR"
            confianca = 30
            mentor_mensagem = "Self-consistency CONFLITO: $t1 vs $t2. Forcado REVISAR (paper-only)."
        }
        return [PSCustomObject]@{
            final = $final
            consistent = $false
            reason = "downgrade_conflict_to_REVISAR"
        }
    }

    # Same side but different strength -> downgrade pro mais conservador
    if ($s1 -eq "bull" -and $s2 -eq "bull") {
        # STRONG vs EXECUTAR -> EXECUTAR
        $final = [PSCustomObject]@{
            decision = "APROVAR"
            veredicto_5tier = "EXECUTAR"
            confianca = [Math]::Min([int]$First.confianca, [int]$Second.confianca)
            mentor_mensagem = "Self-consistency: ambos APROVAR mas magnitudes diferiram ($t1/$t2). Downgrade pra EXECUTAR safe."
        }
        return [PSCustomObject]@{
            final = $final
            consistent = $false
            reason = "downgrade_to_EXECUTAR"
        }
    }
    if ($s1 -eq "bear" -and $s2 -eq "bear") {
        # HARD_VETO vs ABORTAR -> ABORTAR (sem blacklist 24h)
        $final = [PSCustomObject]@{
            decision = "VETAR"
            veredicto_5tier = "ABORTAR"
            confianca = [Math]::Min([int]$First.confianca, [int]$Second.confianca)
            mentor_mensagem = "Self-consistency: ambos VETAR mas magnitudes diferiram ($t1/$t2). Downgrade pra ABORTAR (no blacklist)."
        }
        return [PSCustomObject]@{
            final = $final
            consistent = $false
            reason = "downgrade_to_ABORTAR"
        }
    }

    # Catchall (neutral cases) -> First wins
    return [PSCustomObject]@{
        final = $First
        consistent = $false
        reason = "neutral_fallback_keep_first"
    }
}
