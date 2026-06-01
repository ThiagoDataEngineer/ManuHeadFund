# lib_staleness_engine.ps1 -- Multi-trigger detector + priority scoring + rerun cmd.
#
# Phase 0b (2026-05-23): identifica automaticamente o que precisa rodar novamente
# baseado em 5 triggers: capital drift, time-age, source-data mtime, lib version, config change.
#
# Funcoes:
#   - Get-StaleItems: itera registry + flags stale com reason+priority+rerun_cmd
#   - Write-StalenessAudit: produz journal/staleness_audit.json + history
#   - Test-Stale-CapitalSensitive: capital drift trigger
#   - Test-Stale-TimeBased: age trigger
#   - Test-Stale-SourceDataChanged: mtime newer than item
#
# Registry: $script:STALENESS_REGISTRY (extensible)
#
# PS 5.1. UTF-8 BOM.


# Registry hard-coded — items rastreados pra staleness
$script:STALENESS_REGISTRY = @(
    @{
        name = "per_asset_whitelist"
        item_pattern = "per_asset_whitelist_*.json"
        rerun_cmd = "powershell -File scripts/rebuild_per_asset_whitelist.ps1"
        capital_sensitive = $true
        time_sensitive = $true
        max_age_days = 30
        source_paths = @("journal/candles_coinex")
        auto_safe = $true
        priority_base = "HIGH"
    },
    @{
        name = "wyckoff_market_quality"
        item_pattern = "wyckoff_market_quality.json"
        rerun_cmd = "python backtest/wyckoff_spring_score.py --rebuild-quality"
        capital_sensitive = $false
        time_sensitive = $true
        max_age_days = 60
        source_paths = @("journal/candles_coinex")
        auto_safe = $true
        priority_base = "MEDIUM"
    },
    @{
        name = "dsr_global"
        item_pattern = "dsr_global.json"
        rerun_cmd = "echo 'dsr_global recompute requires careful review'"
        capital_sensitive = $true
        time_sensitive = $true
        max_age_days = 90
        source_paths = @()
        auto_safe = $false  # affects sizing, manual review
        priority_base = "MEDIUM"
    },
    @{
        name = "beta_vs_btc"
        item_pattern = "beta_vs_btc.json"
        rerun_cmd = "powershell -File scripts/build_beta_cache.ps1"
        capital_sensitive = $false
        time_sensitive = $true
        max_age_days = 14
        source_paths = @("journal/candles_coinex")
        auto_safe = $true
        priority_base = "LOW"
    },
    @{
        name = "regime_state"
        item_pattern = "regime_state.json"
        rerun_cmd = "powershell -File scripts/refresh_regime_state.ps1"
        capital_sensitive = $false
        time_sensitive = $true
        max_age_days = 7
        source_paths = @()
        auto_safe = $true
        priority_base = "MEDIUM"
    }
)


function Get-StalenessRegistry { return ,$script:STALENESS_REGISTRY }


function Test-Stale-CapitalSensitive {
    <#
    .SYNOPSIS
    True se item eh capital_sensitive AND capital drifted > Threshold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [double] $DriftPct = 0
    )
    if (-not $Item.capital_sensitive) { return $false }
    return ([math]::Abs($DriftPct) -gt 30)
}


function Test-Stale-TimeBased {
    <#
    .SYNOPSIS
    True se file mtime older than item.max_age_days.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [string] $JournalDir
    )
    if (-not $Item.time_sensitive) { return $false }
    $files = @(Get-ChildItem -Path $JournalDir -Filter $Item.item_pattern -ErrorAction SilentlyContinue)
    if (-not $files) { return $true }  # missing = stale by definition
    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $age = ((Get-Date) - $newest.LastWriteTime).TotalDays
    return ($age -gt $Item.max_age_days)
}


function Test-Stale-SourceDataChanged {
    <#
    .SYNOPSIS
    True se source_path mtime newer than item mtime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Item,
        [Parameter(Mandatory)] [string] $JournalDir,
        [string] $ProjectRoot = "."
    )
    if (-not $Item.source_paths -or $Item.source_paths.Count -eq 0) { return $false }
    $files = @(Get-ChildItem -Path $JournalDir -Filter $Item.item_pattern -ErrorAction SilentlyContinue)
    if (-not $files) { return $true }
    $itemMtime = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    foreach ($srcPath in $Item.source_paths) {
        $full = Join-Path $ProjectRoot $srcPath
        if (-not (Test-Path $full)) { continue }
        $srcFiles = @(Get-ChildItem -Path $full -Recurse -File -ErrorAction SilentlyContinue)
        if (-not $srcFiles) { continue }
        $srcNewest = ($srcFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        if ($srcNewest -gt $itemMtime) { return $true }
    }
    return $false
}


function Get-StaleItems {
    <#
    .SYNOPSIS
    Itera registry + checks all triggers + returns priorized list.

    .PARAMETER JournalDir
    Default = global:JOURNAL_DIR ou ./journal.

    .PARAMETER ProjectRoot
    Default = current dir.

    .PARAMETER DriftPct
    Drift atual (pode passar de Get-CapitalDrift result). 0 = ignora capital trigger.

    .OUTPUTS
    Array de PSCustomObject @{name, reasons[], priority, rerun_cmd, auto_safe, ...}
    #>
    [CmdletBinding()]
    param(
        [string] $JournalDir = "",
        [string] $ProjectRoot = ".",
        [double] $DriftPct = 0
    )
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $ProjectRoot "journal" }
    }

    $results = @()
    foreach ($item in $script:STALENESS_REGISTRY) {
        $reasons = @()
        if (Test-Stale-CapitalSensitive -Item $item -DriftPct $DriftPct) {
            $reasons += "capital_drift_$([math]::Round($DriftPct,0))pct"
        }
        if (Test-Stale-TimeBased -Item $item -JournalDir $JournalDir) {
            $reasons += "age_above_$($item.max_age_days)d"
        }
        if (Test-Stale-SourceDataChanged -Item $item -JournalDir $JournalDir -ProjectRoot $ProjectRoot) {
            $reasons += "source_data_changed"
        }

        if ($reasons.Count -gt 0) {
            # Priority bumping: HIGH if multiple triggers + capital_sensitive
            $priority = $item.priority_base
            if ($reasons.Count -ge 2 -and $item.capital_sensitive) {
                $priority = "HIGH"
            }
            $results += [PSCustomObject]@{
                name = $item.name
                priority = $priority
                reasons = @($reasons)
                rerun_cmd = $item.rerun_cmd
                auto_safe = [bool]$item.auto_safe
            }
        }
    }

    # Sort by priority HIGH > MEDIUM > LOW
    $order = @{ HIGH=0; MEDIUM=1; LOW=2 }
    $sorted = $results | Sort-Object @{ Expression={ $order[$_.priority] } }, name
    return @($sorted)
}


function Write-StalenessAudit {
    <#
    .SYNOPSIS
    Produz audit JSON em journal/staleness_audit.json + append history.

    .OUTPUTS
    PSCustomObject (mesmo do JSON written).
    #>
    [CmdletBinding()]
    param(
        [string] $JournalDir = "",
        [string] $ProjectRoot = ".",
        [double] $DriftPct = 0,
        [hashtable] $CapitalSnapshot = @{}
    )
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $ProjectRoot "journal" }
    }

    $items = Get-StaleItems -JournalDir $JournalDir -ProjectRoot $ProjectRoot -DriftPct $DriftPct
    $audit = [PSCustomObject]@{
        audit_ts = (Get-Date).ToUniversalTime().ToString("o")
        drift_pct = $DriftPct
        capital_snapshot = $CapitalSnapshot
        items_stale = @($items)
        n_stale = $items.Count
        n_high = @($items | Where-Object { $_.priority -eq "HIGH" }).Count
        n_auto_safe = @($items | Where-Object { $_.auto_safe }).Count
    }
    if (-not (Test-Path $JournalDir)) { New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null }
    $outPath = Join-Path $JournalDir "staleness_audit.json"
    $histPath = Join-Path $JournalDir "staleness_audit_history.jsonl"
    $audit | ConvertTo-Json -Depth 6 | Out-File -FilePath $outPath -Encoding utf8 -Force
    # Append to history (compact)
    Add-Content -Path $histPath -Value ($audit | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
    return $audit
}
