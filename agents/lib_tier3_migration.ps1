# agents/lib_tier3_migration.ps1
# Tier 3 migration: Learning state (decision_grades, evolution, regime) → Supabase agent_decisions
#
# Critical system state that MUST be persistent across reboots.
# PS 5.1 compatible.

$_tier3Dir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "journal"

function Migrate-DecisionGrades {
    <#
    .SYNOPSIS
    Import decision_grades.jsonl → manuheadfund.agent_decisions.
    Grades track confidence/outcome of past decisions (aprendizado).

    .PARAMETER SourcePath
    Path to JSONL (default: journal/decision_grades.jsonl)

    .OUTPUTS
    @{ imported=int; errors=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_tier3Dir "decision_grades.jsonl")
    )

    $result = @{
        imported = 0
        errors   = 0
        details  = @()
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Verbose "[tier3] Decision grades not found: $SourcePath"
        return [PSCustomObject]$result
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    try {
        $lines = @(Get-Content $SourcePath | Where-Object {$_})
        Write-Verbose "[tier3] Loaded $($lines.Count) decision grades"
    } catch {
        return [PSCustomObject]$result
    }

    foreach ($line in $lines) {
        try {
            $grade = $line | ConvertFrom-Json

            # Schema mapping: decision_grades → agent_decisions
            # decision_grades has: market, direction, decision, correct, would_win, regime, ts, graded_at, move_dir_d2
            $normalized = @{
                agent_name    = "decision_grades_importer"
                decision_type = "historical_grade"
                symbol        = [string]($grade.market ?? "UNKNOWN")
                direction     = [string]($grade.direction ?? "")
                conviction    = if ($grade.correct) { 0.9 } else { 0.1 }  # Graded as correct=high conviction
                confidence    = if ($grade.would_win) { 0.95 } else { 0.5 }  # would_win=high confidence
                reasoning     = @{
                    market        = $grade.market
                    decision      = $grade.decision
                    correct       = $grade.correct
                    would_win     = $grade.would_win
                    move_dir_d2   = $grade.move_dir_d2
                    regime        = $grade.regime
                }
                outcome       = if ($grade.correct) { "correct" } else { "incorrect" }
                created_at    = if ($grade.graded_at) { [datetime]::Parse($grade.graded_at) } else { (Get-Date) }
                decided_at    = if ($grade.ts) { [datetime]::Parse($grade.ts) } else { (Get-Date) }
            }

            Save-StateRecords -Table "agent_decisions" -Records @($normalized) -PrimaryKey $null | Out-Null
            $result.imported++

        } catch {
            $result.errors++
            $result.details += @{ symbol = $grade.market ?? "unknown"; error = $_ }
        }
    }

    Write-Verbose "[tier3] DecisionGrades: imported=$($result.imported), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Migrate-EvolutionState {
    <#
    .SYNOPSIS
    Import evolution_*.json (multipliers, rebalances) → agent_decisions.
    Tracks evolution engine state (learning + adaptation).

    .PARAMETER SourceDir
    Directory containing evolution_*.json files (default: journal/)

    .OUTPUTS
    @{ imported=int; errors=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourceDir = $_tier3Dir
    )

    $result = @{
        imported = 0
        errors   = 0
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    $evoFiles = @(Get-ChildItem "$SourceDir/evolution_*.json" -ErrorAction SilentlyContinue)
    Write-Verbose "[tier3] Found $($evoFiles.Count) evolution files"

    foreach ($file in $evoFiles) {
        try {
            $data = Get-Content $file.FullName -Raw | ConvertFrom-Json

            $normalized = @{
                id            = [string]($data.id ?? $file.BaseName)
                agent_name    = "evolution_engine"
                decision_type = "adaptation"
                conviction    = [double]($data.score ?? 0)
                confidence    = [double]($data.confidence ?? 0)
                reasoning     = @{
                    file     = $file.Name
                    timestamp = $data.timestamp
                    data     = $data
                }
                outcome       = "applied"
                created_at    = $file.CreationTime
                decided_at    = $file.LastWriteTime
            }

            Save-StateRecords -Table "agent_decisions" -Records @($normalized) -PrimaryKey "id" | Out-Null
            $result.imported++

        } catch {
            $result.errors++
        }
    }

    Write-Verbose "[tier3] Evolution: imported=$($result.imported), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Migrate-RegimeState {
    <#
    .SYNOPSIS
    Import regime_state.json → daily_reconciliation or agent_decisions.
    Current market regime (BEAR_WEAK, BULL_STRONG, etc.) is critical context.

    .PARAMETER SourcePath
    Path to regime_state.json

    .OUTPUTS
    @{ imported=int; errors=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_tier3Dir "regime_state.json")
    )

    $result = @{
        imported = 0
        errors   = 0
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Verbose "[tier3] Regime state not found"
        return [PSCustomObject]$result
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    try {
        $regime = Get-Content $SourcePath -Raw | ConvertFrom-Json

        # Store in daily_reconciliation table (regime per day)
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $normalized = @{
            reconcile_date   = [datetime]::Parse($today)
            regime           = [string]($regime.regime ?? $regime.current ?? "UNKNOWN")
            total_trades_day = 0  # Will update as trades come in
            win_count        = 0
            loss_count       = 0
            pnl_realized     = 0
        }

        Save-StateRecords -Table "daily_reconciliation" -Records @($normalized) -PrimaryKey "reconcile_date" | Out-Null
        $result.imported++

    } catch {
        $result.errors++
    }

    Write-Verbose "[tier3] Regime: imported=$($result.imported), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Get-Tier3Status {
    <#
    .SYNOPSIS
    Report Tier 3 migration: local learning files vs cloud agent_decisions.

    .OUTPUTS
    @{ decision_grades_local=int; decision_grades_cloud=int; evolution_files_local=int; evolution_cloud=int; regime_local=bool; regime_cloud=bool }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $status = @{
        decision_grades_local  = 0
        decision_grades_cloud  = 0
        evolution_files_local  = 0
        evolution_cloud        = 0
        regime_local           = $false
        regime_cloud           = $false
    }

    # Local counts
    $dgPath = Join-Path $_tier3Dir "decision_grades.jsonl"
    if (Test-Path $dgPath) {
        $status.decision_grades_local = @(Get-Content $dgPath | Where-Object {$_}).Count
    }

    $evoFiles = @(Get-ChildItem "$_tier3Dir/evolution_*.json" -ErrorAction SilentlyContinue)
    $status.evolution_files_local = $evoFiles.Count

    $regimePath = Join-Path $_tier3Dir "regime_state.json"
    $status.regime_local = Test-Path $regimePath

    # Cloud counts
    if (Get-Command "Get-StateRecords" -EA SilentlyContinue) {
        try {
            $decisions = @(Get-StateRecords -Table "agent_decisions" -ErrorAction SilentlyContinue)
            $status.decision_grades_cloud = @($decisions | Where-Object { $_.agent_name -eq "unknown" -or $_.decision_type -eq "evaluation" }).Count
            $status.evolution_cloud = @($decisions | Where-Object { $_.agent_name -eq "evolution_engine" }).Count

            $dailies = @(Get-StateRecords -Table "daily_reconciliation" -ErrorAction SilentlyContinue)
            $status.regime_cloud = $dailies.Count -gt 0
        } catch {}
    }

    return [PSCustomObject]$status
}

function Remove-LocalTier3Files {
    <#
    .SYNOPSIS
    DESTRUCTIVE: Remove local learning files after successful cloud migration.
    Only call after validating Tier 3 import succeeded.

    .PARAMETER Confirm
    If $false, remove WITHOUT asking (default $true = ask first)

    .OUTPUTS
    @{ removed=int; failed=int; skipped=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [bool]$Confirm = $true
    )

    $result = @{
        removed = 0
        failed  = 0
        skipped = 0
    }

    # Files to remove
    $filesToRemove = @(
        "decision_grades.jsonl",
        "evolution_history.jsonl",
        "evolution_params.json",
        "evolution_rebalances.jsonl",
        "regime_state.json",
        "gem_recent_decisions.json",
        "gem_recent_decisions.json.bak"
    )

    foreach ($file in $filesToRemove) {
        $path = Join-Path $_tier3Dir $file
        if (-not (Test-Path $path)) {
            $result.skipped++
            continue
        }

        try {
            if ($Confirm) {
                Write-Host "Remove $file? (y/n)" -ForegroundColor Yellow
                $response = Read-Host
                if ($response -ne "y") {
                    $result.skipped++
                    continue
                }
            }

            Remove-Item $path -Force -ErrorAction Stop
            Write-Verbose "[tier3] Removed: $file"
            $result.removed++

        } catch {
            $result.failed++
        }
    }

    return [PSCustomObject]$result
}
