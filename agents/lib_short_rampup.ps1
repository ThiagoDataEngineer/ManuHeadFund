# lib_short_rampup.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-ShortRampupCheck {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] [int] $Phase,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $rampupPath = Join-Path $JournalDir "short_rampup.jsonl"

    $shortEnabled = $false
    $maxLossPct = 0
    $positionSizePct = 0
    $reason = ""

    # Phase gate: SHORT only BULL_WEAK or BULL (not BEAR)
    if ($Regime -match "BEAR" -and $Phase -eq 0) {
        $shortEnabled = $false
        $reason = "SHORT bloqueado em regime $Regime"
    } elseif ($Regime -match "BULL" -and $Phase -ge 1) {
        $shortEnabled = $true

        # Phase 1: tight stops, 2% max loss, 50% position
        if ($Phase -eq 1) {
            $maxLossPct = 2
            $positionSizePct = 0.5
        }
        # Phase 2+: expanded, 4% max loss, full position
        else {
            $maxLossPct = 4
            $positionSizePct = 1.0
        }
    }

    # Log to JSONL
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        regime = $Regime
        phase = $Phase
        short_enabled = $shortEnabled
        max_loss_pct = $maxLossPct
        position_size_pct = $positionSizePct
        reason = $reason
    } | ConvertTo-Json -Compress

    Add-Content -Path $rampupPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        short_enabled = $shortEnabled
        max_loss_pct = $maxLossPct
        position_size_pct = $positionSizePct
        reason = $reason
        market = $Market
        phase = $Phase
    }
}

function Invoke-ShortEnsemble {
    param(
        [Parameter(Mandatory)] [string[]] $MentorVotes
    )

    $shortCount = (@($MentorVotes | Where-Object { $_ -eq "SHORT" })).Count
    $total = $MentorVotes.Count
    $consensus = if ($shortCount -ge ($total / 2)) { "SHORT" } else { "SKIP" }
    $confidence = [Math]::Round($shortCount / $total, 2)

    return [PSCustomObject]@{
        consensus = $consensus
        confidence = $confidence
        votes = @{
            SHORT = $shortCount
            SKIP = ($total - $shortCount)
        }
    }
}
