# agents/lib_bulk_import.ps1
# Bulk import local data → Supabase (migration layer)
#
# Handles deduplication, transformation, and upsert semantics.
# PS 5.1 compatible. UTF-8 BOM tolerated.

$_bulkImportDir = Split-Path $PSScriptRoot -Parent | Join-Path -ChildPath "journal"

function Bulk-Import-TradeOutcomes {
    <#
    .SYNOPSIS
    Import local trade_outcomes.jsonl → Supabase manuheadfund.trade_outcomes.
    Deduplicates by ID, skips existing, logs results.

    .PARAMETER SourcePath
    Path to source JSONL file (default: journal/trade_outcomes.jsonl)

    .PARAMETER SkipExisting
    Skip if record ID already exists in Supabase (default $true)

    .OUTPUTS
    @{ imported=int; skipped=int; errors=int; details=@(...) }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_bulkImportDir "trade_outcomes.jsonl"),
        [bool]$SkipExisting = $true
    )

    $result = @{
        imported = 0
        skipped  = 0
        errors   = 0
        details  = @()
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Verbose "[bulk_import] Source not found: $SourcePath"
        return [PSCustomObject]$result
    }

    try {
        $lines = @(Get-Content $SourcePath | Where-Object {$_})
        Write-Verbose "[bulk_import] Loaded $($lines.Count) lines from $SourcePath"
    } catch {
        Write-Verbose "[bulk_import] Read error: $_"
        return [PSCustomObject]$result
    }

    # Load state store for Supabase ops
    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        Write-Verbose "[bulk_import] State store not loaded, skipping cloud import"
        return [PSCustomObject]$result
    }

    $existingIds = @{}
    if ($SkipExisting) {
        try {
            $existing = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction SilentlyContinue)
            $existing | ForEach-Object { $existingIds[$_.id] = $true }
            Write-Verbose "[bulk_import] Found $($existing.Count) existing records in Supabase"
        } catch {
            Write-Verbose "[bulk_import] Could not fetch existing: $_"
        }
    }

    foreach ($line in $lines) {
        try {
            $trade = $line | ConvertFrom-Json -ErrorAction Stop

            # Normalize ID if missing
            if (-not $trade.id) {
                $trade | Add-Member -Name "id" -Value "$(Get-Date -Format 'yyyyMMddHHmmss')|$($trade.symbol)|$($trade.direction)|$(Get-Random)" -MemberType NoteProperty -Force
            }

            # Skip if exists
            if ($SkipExisting -and $existingIds[$trade.id]) {
                $result.skipped++
                continue
            }

            # Normalize fields (handle multiple schema formats)
            $symbol = [string]($trade.symbol ?? $trade.market ?? "UNKNOWN")
            $entryTs = $trade.entry_ts ?? $trade.entry_time
            if ($entryTs -and $entryTs -isnot [datetime]) {
                $entryTs = [datetime]::Parse($entryTs)
            }

            # Map pnl_usd → pnl_realized for local position syncs
            $pnlRealized = [double]($trade.pnl_realized ?? $trade.pnl_usd ?? 0)

            $normalized = @{
                id               = [string]($trade.id ?? $trade.trade_id ?? "unknown_$(Get-Random)")
                entry_ts         = $entryTs ?? (Get-Date)
                symbol           = $symbol
                direction        = [string]($trade.direction ?? "LONG")
                source           = [string]($trade.source ?? "bulk_import")
                entry_price      = [double]($trade.entry_price ?? 0)
                exit_price       = [double]($trade.exit_price ?? 0)
                quantity         = [double]($trade.quantity ?? $trade.size_usd ?? 0)
                pnl_realized     = $pnlRealized
                pnl_percent      = [double]($trade.pnl_percent ?? $trade.pnl_pct ?? 0)
                status           = [string]($trade.status ?? "pending")
                regime           = [string]($trade.regime ?? "")
                has_confluence   = [bool]($trade.has_confluence ?? $false)
                conviction_score = [double]($trade.conviction_score ?? 0)
            }

            # Save to Supabase
            $saved = Save-StateRecords -Table "trade_outcomes" -Records @($normalized) -PrimaryKey "id" -ErrorAction Stop
            if ($saved) {
                $result.imported++
            } else {
                $result.errors++
                $result.details += @{ symbol = $normalized.symbol; error = "Save returned false" }
            }
        } catch {
            $result.errors++
            $result.details += @{ symbol = $trade.symbol ?? "unknown"; error = $_ }
        }
    }

    Write-Verbose "[bulk_import] Complete: imported=$($result.imported), skipped=$($result.skipped), errors=$($result.errors)"
    return [PSCustomObject]$result
}

function Bulk-Import-OpenPositions {
    <#
    .SYNOPSIS
    Import local open_positions_tracking.jsonl → Supabase manuheadfund.open_positions.

    .PARAMETER SourcePath
    Path to source JSONL file

    .OUTPUTS
    @{ imported=int; skipped=int; errors=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$SourcePath = (Join-Path $_bulkImportDir "open_positions_tracking.jsonl")
    )

    $result = @{
        imported = 0
        skipped  = 0
        errors   = 0
    }

    if (-not (Test-Path $SourcePath)) {
        return [PSCustomObject]$result
    }

    if (-not (Get-Command "Get-StateRecords" -EA SilentlyContinue)) {
        return [PSCustomObject]$result
    }

    try {
        $lines = @(Get-Content $SourcePath | Where-Object {$_})
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
                $result.skipped++
                continue
            }

            $normalized = @{
                id           = [string]$pos.id
                symbol       = [string]$pos.symbol
                direction    = [string]$pos.direction
                entry_price  = [double]$pos.entry_price
                quantity     = [double]$pos.quantity
                stop_loss    = [double]($pos.stop_loss ?? 0)
                take_profit  = [double]($pos.take_profit ?? 0)
                entered_at   = [datetime]::Parse($pos.entered_at)
                status       = [string]($pos.status ?? "active")
                source       = "bulk_import"
            }

            Save-StateRecords -Table "open_positions" -Records @($normalized) -PrimaryKey "id" | Out-Null
            $result.imported++
        } catch {
            $result.errors++
        }
    }

    return [PSCustomObject]$result
}

function Get-BulkImportStatus {
    <#
    .SYNOPSIS
    Check migration status: local vs Supabase record counts.

    .OUTPUTS
    @{ trade_outcomes_local=int; trade_outcomes_cloud=int; open_positions_local=int; open_positions_cloud=int }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $status = @{
        trade_outcomes_local     = 0
        trade_outcomes_cloud     = 0
        open_positions_local     = 0
        open_positions_cloud     = 0
    }

    # Local counts
    $toPath = Join-Path $_bulkImportDir "trade_outcomes.jsonl"
    if (Test-Path $toPath) {
        $status.trade_outcomes_local = @(Get-Content $toPath | Where-Object {$_}).Count
    }

    $opPath = Join-Path $_bulkImportDir "open_positions_tracking.jsonl"
    if (Test-Path $opPath) {
        $status.open_positions_local = @(Get-Content $opPath | Where-Object {$_}).Count
    }

    # Cloud counts
    if (Get-Command "Get-StateRecords" -EA SilentlyContinue) {
        try {
            $status.trade_outcomes_cloud = @(Get-StateRecords -Table "trade_outcomes" -ErrorAction SilentlyContinue).Count
            $status.open_positions_cloud = @(Get-StateRecords -Table "open_positions" -ErrorAction SilentlyContinue).Count
        } catch {}
    }

    return [PSCustomObject]$status
}
