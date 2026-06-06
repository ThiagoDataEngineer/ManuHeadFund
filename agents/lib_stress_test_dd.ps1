# lib_stress_test_dd.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-StressTestDD {
    param(
        [Parameter(Mandatory)] [double] $CurrentDD,
        [Parameter(Mandatory)] [int] $BasePositionSize,
        [string[]] $DaemonsToHalt = @("gem_loop", "scan_master", "telegram_listener", "watchdog_paper", "faro_v3_schedule"),
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $stressPath = Join-Path $JournalDir "stress_test_dd.jsonl"

    $action = "NORMAL"
    $newPositionSize = $BasePositionSize
    $haltedDaemons = @()
    $haltReason = ""

    # DD >= 15% = HALT all daemons
    if ($CurrentDD -le -15) {
        $action = "HALT"
        $haltReason = "DD >= 15%: emergency stop"
        $haltedDaemons = $DaemonsToHalt
    }
    # DD >= 10% = REDUCE 50%
    elseif ($CurrentDD -le -10) {
        $action = "REDUCE_50"
        $newPositionSize = [Math]::Floor($BasePositionSize * 0.5)
    }
    # DD < 10% = NORMAL
    else {
        $action = "NORMAL"
    }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        current_dd = $CurrentDD
        action = $action
        base_position_size = $BasePositionSize
        new_position_size = $newPositionSize
        halt_reason = $haltReason
        halted_daemons = ($haltedDaemons -join ",")
    } | ConvertTo-Json -Compress

    Add-Content -Path $stressPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        action = $action
        new_position_size = $newPositionSize
        halt_reason = $haltReason
        halted_daemons = $haltedDaemons
        current_dd = $CurrentDD
    }
}

function Test-DrawdownThreshold {
    param(
        [double] $CurrentDD,
        [int] $Threshold = 15
    )

    return $CurrentDD -le (-1 * $Threshold)
}
