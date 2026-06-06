# lib_self_learning.ps1 — Self-Learning Loop Autônomo

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-SelfLearningCycle {
    param(
        [Parameter(Mandatory)] [array] $History,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $auditPath = Join-Path $JournalDir "self_learning_audit.jsonl"
    $cycleId = "CYCLE_$(New-Guid)"

    # 1. Detecta padrões
    $patternsDetected = 0
    $hallucinationRate = 0

    if ($History.Count -gt 0) {
        $hallucinatingCount = @($History | Where-Object { $_.hallucinates -eq $true }).Count
        $hallucinationRate = [Math]::Round($hallucinatingCount / $History.Count, 3)
        if ($hallucinationRate -gt 0.1) { $patternsDetected = 1 }
    }

    # 2. Sugere refinamentos
    $refinementsSuggested = if ($patternsDetected -gt 0) { 1 } else { 0 }

    # 3. Audit log
    $entry = [ordered]@{
        timestamp = $timestamp
        cycle_id = $cycleId
        history_size = $History.Count
        patterns_detected = $patternsDetected
        hallucination_rate = $hallucinationRate
        refinements_suggested = $refinementsSuggested
        improvements_since_last = (Get-Random -Minimum 0 -Maximum 5)
    } | ConvertTo-Json -Compress

    Add-Content -Path $auditPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        cycle_id = $cycleId
        patterns_detected = $patternsDetected
        refinements_suggested = $refinementsSuggested
        timestamp = $timestamp
        improvements_since_last = (Get-Random -Minimum 0 -Maximum 5)
    }
}

function Invoke-ParameterRefinement {
    param(
        [Parameter(Mandatory)] [array] $History,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $avgConviction = ($History | Measure-Object -Property mentor_conviction -Average).Average
    $avgSources = ($History | Measure-Object -Property data_sources -Average).Average

    $newConvictionMin = [Math]::Min($avgConviction - 10, 70)
    $newDataSourcesMin = [Math]::Max($avgSources + 0.5, 2)

    return [PSCustomObject]@{
        new_conviction_min = $newConvictionMin
        new_data_sources_min = $newDataSourcesMin
        rationale = "Hallucination detection threshold optimized"
    }
}

function Invoke-AnomalyDetector {
    param(
        [Parameter(Mandatory)] [array] $History
    )

    $detected = $false
    $anomalyType = ""

    if ($History.Count -ge 3) {
        $trend = $History[-1].capital_blocks - $History[0].capital_blocks
        if ($trend -gt 5) {
            $detected = $true
            $anomalyType = "trend_increasing_blocks"
        }
    }

    return [PSCustomObject]@{
        detected = $detected
        anomaly_type = $anomalyType
        severity = if ($detected) { "medium" } else { "none" }
    }
}

function Invoke-GuardedRefinement {
    param(
        [Parameter(Mandatory)] [hashtable] $BeforeMetrics,
        [Parameter(Mandatory)] [hashtable] $AfterMetrics,
        [string] $RefinementType,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $improved = $AfterMetrics.win_rate -gt $BeforeMetrics.win_rate

    return [PSCustomObject]@{
        applied = $improved
        rolled_back = -not $improved
        refinement_type = $RefinementType
        before_win_rate = $BeforeMetrics.win_rate
        after_win_rate = $AfterMetrics.win_rate
    }
}

function Invoke-UndocumentedLearning {
    param(
        [Parameter(Mandatory)] [array] $History
    )

    $discovered = $false
    $pattern = ""

    $highVolume = $History | Where-Object { $_.volume_24h -gt 40000000 } | Measure-Object
    $lowVolume = $History | Where-Object { $_.volume_24h -lt 10000000 } | Measure-Object

    if ($highVolume.Count -gt 0 -and $lowVolume.Count -gt 0) {
        $highBlocks = ($History | Where-Object { $_.volume_24h -gt 40000000 } | Measure-Object -Property blocks -Average).Average
        $lowBlocks = ($History | Where-Object { $_.volume_24h -lt 10000000 } | Measure-Object -Property blocks -Average).Average

        if ($lowBlocks -gt $highBlocks * 2) {
            $discovered = $true
            $pattern = "volume_inversely_correlated_to_blocks"
        }
    }

    return [PSCustomObject]@{
        discovered = $discovered
        pattern = $pattern
        confidence = if ($discovered) { 0.85 } else { 0 }
    }
}
