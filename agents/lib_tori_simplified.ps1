# lib_tori_simplified.ps1
# BLOCKER #4 FIX: Tori logic consistency
# 2026-06-18: Remove CONVICTION_GATE.flag bypass, use mesa_score instead

function Get-ToriRequirement {
    <#
    .SYNOPSIS
        Determine if Tori is REQUIRED or OPTIONAL
        - Mesa score 75+ = Tori optional (strong enough without Tori)
        - Mesa score 60-75 = Tori required but less strict (still need technical anchor)
        - Mesa score <60 = Tori required (need technical confirmation)
    .PARAMETER MesaScore
        Mesa consensus score (0-100)
    .PARAMETER Signal
        Expected Tori signal (ENTER/SKIP/WAIT)
    .OUTPUTS
        PSCustomObject:
          required: $true/$false (is Tori required?)
          allows_skip: can trade proceed if Tori=SKIP?
          reason: explanation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [int]$MesaScore,
        [Parameter(Mandatory=$false)] [string]$Signal = "UNKNOWN"
    )

    if ($MesaScore -gt 75) {
        # Elite signal: Tori is optional
        return @{
            required = $false
            allows_skip = $true
            allows_wait = $true
            reason = "mesa_elite_75plus_tori_optional"
        }
    }
    elseif ($MesaScore -gt 60) {
        # Strong signal: Tori required but less strict
        return @{
            required = $true
            allows_skip = $false  # SKIP is still a blocker
            allows_wait = $true   # WAIT is acceptable (can wait for better signal)
            reason = "mesa_strong_60to75_tori_required_but_less_strict"
        }
    }
    else {
        # Normal signal: Tori required and strict
        return @{
            required = $true
            allows_skip = $false
            allows_wait = $false  # WAIT blocks entry
            reason = "mesa_normal_below60_tori_strictly_required"
        }
    }
}

function Test-ToriGateConsistent {
    <#
    .SYNOPSIS
        Test if Tori signal is acceptable given mesa score
    .PARAMETER MesaScore
        Mesa consensus score
    .PARAMETER ToriSignal
        Tori response (ENTER/SKIP/WAIT/ERROR)
    .OUTPUTS
        PSCustomObject:
          pass: $true/$false
          reason: why it passed or failed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [int]$MesaScore,
        [Parameter(Mandatory=$true)] [string]$ToriSignal
    )

    $req = Get-ToriRequirement -MesaScore $MesaScore

    if ($ToriSignal -eq "ENTER") {
        return @{ pass = $true; reason = "tori_enter_always_ok" }
    }
    elseif ($ToriSignal -eq "SKIP") {
        if ($req.allows_skip) {
            return @{ pass = $true; reason = "tori_skip_ok_for_elite_mesa_$MesaScore" }
        } else {
            return @{ pass = $false; reason = "tori_skip_blocks_mesa_$MesaScore" }
        }
    }
    elseif ($ToriSignal -eq "WAIT") {
        if ($req.allows_wait) {
            return @{ pass = $true; reason = "tori_wait_acceptable_for_strong_mesa_$MesaScore" }
        } else {
            return @{ pass = $false; reason = "tori_wait_blocks_mesa_$MesaScore" }
        }
    }
    else {
        return @{ pass = $false; reason = "tori_error_or_unknown_signal_$ToriSignal" }
    }
}
