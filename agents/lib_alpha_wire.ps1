# lib_alpha_wire.ps1 -- Wire alpha_vs_btc no trades.csv (E4 close-trade migration).
#
# Funcoes:
#   - Test-AlphaColumnExists: check se header tem alpha_vs_btc
#   - Add-AlphaColumnToCsv: schema migration (backup + append column)
#   - Update-TradeWithAlpha: write alpha_vs_btc no row de trade fechado
#
# Pattern: backup-before-modify, idempotent, fail-soft.
#
# PS 5.1. UTF-8 BOM.


function Test-AlphaColumnExists {
    <#
    .SYNOPSIS
    Retorna $true se CSV header contem 'alpha_vs_btc' coluna.

    .PARAMETER CsvPath
    Path to CSV file.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $CsvPath)
    if (-not (Test-Path $CsvPath)) { return $false }
    try {
        $lines = @(Get-Content $CsvPath -Encoding UTF8 -ErrorAction Stop)
        if ($lines.Count -eq 0) { return $false }
        # Strip BOM if present
        $header = $lines[0] -replace [char]0xFEFF, ""
        return ($header -split "," | ForEach-Object { $_.Trim() }) -contains "alpha_vs_btc"
    } catch {
        return $false
    }
}


function Add-AlphaColumnToCsv {
    <#
    .SYNOPSIS
    Add 'alpha_vs_btc' column ao final do CSV. Backup automatico antes.

    .DESCRIPTION
    Idempotente: se ja existe, returns $false (no-op).
    Backup: {CsvPath}.bak_{yyyyMMdd_HHmmss}

    .PARAMETER CsvPath
    Path to CSV.

    .OUTPUTS
    PSCustomObject @{ migrated, backup_path, rows_updated, reason }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $CsvPath)

    if (-not (Test-Path $CsvPath)) {
        return [PSCustomObject]@{
            migrated = $false; backup_path = ""; rows_updated = 0; reason = "file_not_found"
        }
    }
    if (Test-AlphaColumnExists -CsvPath $CsvPath) {
        return [PSCustomObject]@{
            migrated = $false; backup_path = ""; rows_updated = 0; reason = "already_exists"
        }
    }

    # Backup
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup = "$CsvPath.bak_$ts"
    Copy-Item -Path $CsvPath -Destination $backup -Force

    try {
        $lines = @(Get-Content $CsvPath -Encoding UTF8 -ErrorAction Stop)
        if ($lines.Count -eq 0) {
            return [PSCustomObject]@{
                migrated = $false; backup_path = $backup; rows_updated = 0; reason = "empty_file"
            }
        }
        $newLines = @()
        # Header
        $header = $lines[0]
        $newLines += "$header,alpha_vs_btc"
        # Existing rows: append empty alpha
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $row = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($row)) { $newLines += $row; continue }
            $newLines += "$row,"
        }
        $newLines | Out-File -FilePath $CsvPath -Encoding UTF8 -Force
        return [PSCustomObject]@{
            migrated = $true
            backup_path = $backup
            rows_updated = $lines.Count - 1
            reason = "ok"
        }
    } catch {
        # Restore backup on failure
        Copy-Item -Path $backup -Destination $CsvPath -Force
        return [PSCustomObject]@{
            migrated = $false
            backup_path = $backup
            rows_updated = 0
            reason = "error: $($_.Exception.Message)"
        }
    }
}


function Update-TradeWithAlpha {
    <#
    .SYNOPSIS
    Atualiza row de trade fechado com alpha_vs_btc.

    .DESCRIPTION
    Use APOS Close-Trade ter salvado o row com exit_price/pnl_pct.
    Idempotente: se row ja tem alpha_vs_btc preenchido (nao vazio), retorna no-op.

    .PARAMETER CsvPath
    Path to CSV.

    .PARAMETER TradeId
    ID do trade.

    .PARAMETER AlphaVsBtc
    Valor computado (Nullable double — escreve vazio se null).

    .OUTPUTS
    PSCustomObject @{ updated, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $CsvPath,
        [Parameter(Mandatory)] [string] $TradeId,
        [Nullable[double]] $AlphaVsBtc
    )

    if (-not (Test-Path $CsvPath)) {
        return [PSCustomObject]@{ updated = $false; reason = "file_not_found" }
    }
    if (-not (Test-AlphaColumnExists -CsvPath $CsvPath)) {
        return [PSCustomObject]@{ updated = $false; reason = "column_missing_run_migration_first" }
    }

    try {
        $lines = @(Get-Content $CsvPath -Encoding UTF8 -ErrorAction Stop)
        if ($lines.Count -lt 2) {
            return [PSCustomObject]@{ updated = $false; reason = "empty_csv" }
        }
        $header = $lines[0] -replace [char]0xFEFF, ""
        $cols = $header -split ","
        $alphaIdx = -1
        for ($i = 0; $i -lt $cols.Count; $i++) {
            if ($cols[$i].Trim() -eq "alpha_vs_btc") { $alphaIdx = $i; break }
        }
        if ($alphaIdx -lt 0) {
            return [PSCustomObject]@{ updated = $false; reason = "alpha_col_not_found" }
        }

        $updated = $false
        $newLines = @($lines[0])  # header preserved
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $row = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($row)) { $newLines += $row; continue }
            $rowCols = $row -split ","
            if ($rowCols.Count -gt 0 -and $rowCols[0] -eq $TradeId) {
                # Ensure row has enough columns
                while ($rowCols.Count -le $alphaIdx) {
                    $rowCols += ""
                }
                $alphaStr = if ($null -ne $AlphaVsBtc) { ("{0:0.##}" -f $AlphaVsBtc) } else { "" }
                $rowCols[$alphaIdx] = $alphaStr
                $newLines += ($rowCols -join ",")
                $updated = $true
            } else {
                $newLines += $row
            }
        }
        if ($updated) {
            $newLines | Out-File -FilePath $CsvPath -Encoding UTF8 -Force
            return [PSCustomObject]@{ updated = $true; reason = "ok" }
        } else {
            return [PSCustomObject]@{ updated = $false; reason = "trade_id_not_found" }
        }
    } catch {
        return [PSCustomObject]@{ updated = $false; reason = "error: $($_.Exception.Message)" }
    }
}
