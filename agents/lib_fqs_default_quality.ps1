# lib_fqs_default_quality.ps1
# BLOCKER #5 FIX: FQS missing handling
# 2026-06-18: When FQS unavailable, use sensible defaults instead of rejecting

function Get-FqsQualityOrDefault {
    <#
    .SYNOPSIS
        Get FQS quality score, or default if missing
        - Quality 0-7 scale
        - If missing, return default 4 (acceptable for entry)
    .PARAMETER Gem
        Gem object with fqs field
    .PARAMETER DefaultQuality
        Default quality if FQS missing (1-7, default 4)
    .OUTPUTS
        FQS quality score (0-7)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Gem,
        [Parameter(Mandatory=$false)] [int]$DefaultQuality = 4
    )

    # If FQS exists and is valid
    if ($Gem.PSObject.Properties['fqs'] -and $Gem.fqs) {
        $fqs = [int]$Gem.fqs
        if ($fqs -ge 0 -and $fqs -le 7) {
            return $fqs
        }
    }

    # If FQS missing or invalid, return default
    # Default 4/7 means: "Unknown, but assume decent quality"
    Write-Warning "[FQS DEFAULT] $($Gem.market): FQS missing/invalid, using default quality=$DefaultQuality"
    return $DefaultQuality
}

function Test-FqsGatePassesWithDefault {
    <#
    .SYNOPSIS
        Test if FQS gate passes with default value
        - FQS 5+ normally required for entry
        - With default 4, most gems pass
    .PARAMETER Gem
        Gem object
    .PARAMETER MesaScore
        Mesa score (higher mesa = can accept lower FQS)
    .PARAMETER MinQualityRequired
        Minimum FQS required (default 4, can lower for elite mesa)
    .OUTPUTS
        PSCustomObject: pass=$true/$false, fqs=value, reason
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Gem,
        [Parameter(Mandatory=$false)] [int]$MesaScore = 0,
        [Parameter(Mandatory=$false)] [int]$MinQualityRequired = 4
    )

    $quality = Get-FqsQualityOrDefault -Gem $Gem

    # Adjust minimum for elite mesa
    if ($MesaScore -gt 75) {
        $MinQualityRequired = [Math]::Max(2, $MinQualityRequired - 2)  # Lower bar for elite
    }
    elseif ($MesaScore -lt 50) {
        $MinQualityRequired = [Math]::Min(7, $MinQualityRequired + 1)  # Raise bar for weak
    }

    $pass = $quality -ge $MinQualityRequired

    return @{
        pass = $pass
        fqs = $quality
        min_required = $MinQualityRequired
        reason = if ($pass) { "fqs_passes_$quality`_ge_$MinQualityRequired" } else { "fqs_fails_$quality`_lt_$MinQualityRequired" }
        is_default = $Gem.fqs -eq $null -or $Gem.fqs -eq ""
    }
}

# Export
Export-ModuleMember -Function @("Get-FqsQualityOrDefault", "Test-FqsGatePassesWithDefault")
