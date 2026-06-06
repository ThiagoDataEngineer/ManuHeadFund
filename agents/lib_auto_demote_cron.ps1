# lib_auto_demote_cron.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-AutoDemoteCheck {
    param(
        [Parameter(Mandatory)] [string] $Asset,
        [Parameter(Mandatory)] [string] $CurrentTier,
        [Parameter(Mandatory)] [int] $FlagCount,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $demotionsPath = Join-Path $JournalDir "demotions.jsonl"

    $demoted = $false
    $newTier = $CurrentTier
    $reason = ""

    # Rule: 3 consecutive FLAGs = demote Tier A → B
    if ($FlagCount -ge 3 -and $CurrentTier -eq "A") {
        $demoted = $true
        $newTier = "B"
        $reason = "$FlagCount consecutive FLAGS (threshold=3)"

        # Registra demotion
        $demoEntry = [ordered]@{
            timestamp = $timestamp
            asset = $Asset
            old_tier = $CurrentTier
            new_tier = $newTier
            flag_count = $FlagCount
            reason = $reason
        } | ConvertTo-Json -Compress

        Add-Content -Path $demotionsPath -Value $demoEntry -Encoding UTF8
    }

    return [PSCustomObject]@{
        demoted = $demoted
        new_tier = $newTier
        reason = $reason
        asset = $Asset
        flag_count = $FlagCount
    }
}

function Test-AssetShouldDemote {
    param(
        [int] $FlagCount,
        [int] $Threshold = 3
    )
    return $FlagCount -ge $Threshold
}
