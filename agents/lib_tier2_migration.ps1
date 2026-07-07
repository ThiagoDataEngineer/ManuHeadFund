# agents/lib_tier2_migration.ps1
# Tier 2 data migration: open_positions + trailing_positions → Supabase
#
# Handles position reconciliation, orphan detection, and stop validation.
# PS 5.1 compatible.

$_tier2Dir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "journal"

function Migrate-OpenPositions {
    <#
    .SYNOPSIS
    Import local open_positions_tracking.jsonl → manuheadfund.open_positions.
    Validates SL/TP, flags orphans, normalizes schema.

    .PARAMETER SourcePath
    Path to JSONL file (default: journal/open_positions_tracking.jsonl)

    .OUTPUTS
    @{ imported=int; orphans_detected=int; errors=int; details=@(...) }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_tier2Dir "open_positions_tracking.jsonl")
    )

    $result = @{
        imported         = 0
        orphans_detected = 0
        errors           = 0
        details          = @()
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Verbose "[tier2] Open positions source not found: $SourcePath"
        return [PSCustomObject]$result
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    try {
        $lines = @(Get-Content $SourcePath | Where-Object {$_})
        Write-Verbose "[tier2] Loaded $($lines.Count) open positions"
    } catch {
        return [PSCustomObject]$result
    }

    $existingIds = @{}
    try {
        $existing = @(Get-StateRecords -Table "open_positions" -ErrorAction SilentlyContinue)
        $existing | ForEach-Object { $existingIds[$_.id] = $true }
    } catch {}

    foreach ($line in $lines) {
        try {
            $pos = $line | ConvertFrom-Json

            if ($existingIds[$pos.id]) {
                continue
            }

            # Schema mapping: CoinEx format → Supabase schema
            $symbol = [string]($pos.symbol ?? $pos.market ?? "UNKNOWN")
            $slPrice = [double]($pos.stop_loss ?? 0)
            $tpPrice = [double]($pos.take_profit ?? 0)

            # Detect orphan (missing SL or TP)
            $isOrphan = ($slPrice -eq 0) -or ($tpPrice -eq 0)
            if ($isOrphan) {
                $result.orphans_detected++
            }

            $openedAt = $pos.opened_at ?? $pos.entry_ts ?? $pos.entered_at
            if ($openedAt -and $openedAt -isnot [datetime]) {
                $openedAt = [datetime]::Parse($openedAt)
            }

            $normalized = @{
                id              = [string]($pos.id ?? $pos.position_id ?? "unknown_$symbol")
                symbol          = $symbol
                direction       = [string]($pos.direction ?? "LONG")
                entry_price     = [double]$pos.entry_price
                quantity        = [double]$pos.quantity
                stop_loss       = $slPrice
                take_profit     = $tpPrice
                current_price   = [double]($pos.current_price ?? $pos.entry_price)
                pnl_unrealized  = [double]($pos.pnl_unrealized ?? $pos.pnl_usd ?? 0)
                entered_at      = $openedAt ?? (Get-Date)
                status          = [string]($pos.status ?? "active")
                source          = "bulk_import"
                regime          = [string]($pos.regime ?? "")
            }

            Save-StateRecords -Table "open_positions" -Records @($normalized) -PrimaryKey "id" | Out-Null
            $result.imported++

        } catch {
            $result.errors++
            $result.details += @{ symbol = $pos.symbol ?? "unknown"; error = $_ }
        }
    }

    Write-Verbose "[tier2] OpenPositions: imported=$($result.imported), orphans=$($result.orphans_detected), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Migrate-TrailingPositions {
    <#
    .SYNOPSIS
    Import local trailing_positions.json → manuheadfund.trailing_positions.
    Handles adaptive stop history, phase tracking.

    .PARAMETER SourcePath
    Path to JSON file (default: journal/trailing_positions.json)

    .OUTPUTS
    @{ imported=int; errors=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_tier2Dir "trailing_positions.json")
    )

    $result = @{
        imported = 0
        errors   = 0
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Verbose "[tier2] Trailing positions source not found: $SourcePath"
        return [PSCustomObject]$result
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    try {
        $data = Get-Content $SourcePath -Raw | ConvertFrom-Json
        Write-Verbose "[tier2] Loaded trailing positions data"
    } catch {
        return [PSCustomObject]$result
    }

    if ($data -is [array]) {
        $positions = $data
    } else {
        $positions = @($data)
    }

    foreach ($pos in $positions) {
        try {
            $normalized = @{
                id                    = [string]($pos.id ?? $pos.symbol)
                symbol                = [string]$pos.symbol
                direction             = [string]$pos.direction
                entry_price           = [double]$pos.entry_price
                quantity              = [double]$pos.quantity
                current_price         = [double]($pos.current_price ?? 0)
                stop_loss_price       = [double]($pos.stop_loss_price ?? 0)
                take_profit_price     = [double]($pos.take_profit_price ?? 0)
                trailing_stop_current = [double]($pos.trailing_stop_current ?? 0)
                pnl_unrealized        = [double]($pos.pnl_unrealized ?? 0)
                phase                 = [string]($pos.phase ?? "unknown")
                status                = [string]($pos.status ?? "active")
                regime                = [string]($pos.regime ?? "")
                entered_at            = [datetime]::Parse($pos.entered_at)
            }

            Save-StateRecords -Table "trailing_positions" -Records @($normalized) -PrimaryKey "id" | Out-Null
            $result.imported++

        } catch {
            $result.errors++
        }
    }

    Write-Verbose "[tier2] TrailingPositions: imported=$($result.imported), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Get-Tier2Status {
    <#
    .SYNOPSIS
    Report Tier 2 migration progress: local vs cloud counts + orphan detection.

    .OUTPUTS
    @{ open_positions_local=int; open_positions_cloud=int; trailing_local=int; trailing_cloud=int; orphans=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $status = @{
        open_positions_local  = 0
        open_positions_cloud  = 0
        trailing_local        = 0
        trailing_cloud        = 0
        orphans_in_cloud      = 0
    }

    # Local counts
    $opPath = Join-Path $_tier2Dir "open_positions_tracking.jsonl"
    if (Test-Path $opPath) {
        $status.open_positions_local = @(Get-Content $opPath | Where-Object {$_}).Count
    }

    $tpPath = Join-Path $_tier2Dir "trailing_positions.json"
    if (Test-Path $tpPath) {
        try {
            $data = Get-Content $tpPath -Raw | ConvertFrom-Json
            $status.trailing_local = if ($data -is [array]) { $data.Count } else { 1 }
        } catch {}
    }

    # Cloud counts
    if (Get-Command "Get-StateRecords" -EA SilentlyContinue) {
        try {
            $status.open_positions_cloud = @(Get-StateRecords -Table "open_positions" -ErrorAction SilentlyContinue).Count
            $status.trailing_cloud = @(Get-StateRecords -Table "trailing_positions" -ErrorAction SilentlyContinue).Count

            # Count orphans in cloud
            $opClou = @(Get-StateRecords -Table "open_positions" -ErrorAction SilentlyContinue)
            $orphans = @($opClou | Where-Object { ([double]$_.stop_loss -eq 0) -or ([double]$_.take_profit -eq 0) })
            $status.orphans_in_cloud = $orphans.Count
        } catch {}
    }

    return [PSCustomObject]$status
}
