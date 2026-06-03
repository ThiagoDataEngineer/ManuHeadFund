# lib_ladder_tracker.ps1 -- Performance tracker para Exit Ladders
# Registra entradas com ladder anexada e cada TP/SL hit; agrega por template_id Ã— regime.
# CSV InvariantCulture (sub-dollar safe, sem virgula PT-BR).
# Dot-source: . (Join-Path $PSScriptRoot "lib_ladder_tracker.ps1")

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
}

# Helpers internos -------------------------------------------------------------

function _LadderTracker-EnsureDir {
    if (-not (Test-Path $global:JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
    }
}

function _LadderTracker-InvString {
    param($Value)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return "" }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [bool])   { return $Value.ToString().ToLower() }
    try { return ([decimal]$Value).ToString($inv) }
    catch {
        try { return ([double]$Value).ToString($inv) }
        catch { return [string]$Value }
    }
}

# B11 fix 2026-05-20 PM6+: usar ConvertTo-CsvField unico (lib_csv_utils.ps1).
# _LadderTracker-CsvField mantido como thin wrapper pra back-compat.
if (-not (Get-Command ConvertTo-CsvField -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "lib_csv_utils.ps1")
}
function _LadderTracker-CsvField {
    param([AllowNull()] [string] $Text)
    return (ConvertTo-CsvField $Text)
}

function _LadderTracker-EntryPath {
    return (Join-Path $global:JOURNAL_DIR "ladder_tracker.csv")
}

function _LadderTracker-HitPath {
    return (Join-Path $global:JOURNAL_DIR "ladder_hits.csv")
}

# Add-LadderEntryRecord --------------------------------------------------------
# Quando trade entra com ladder, registra contexto e estrutura da escadaria.
function Add-LadderEntryRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $TemplateId,
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] $Entry,
        $AtrValue   = 0,
        [int] $TpsCount = 0,
        [int] $SlsCount = 0,
        [string] $TradeId = "",
        [string] $Notes  = ""
    )

    _LadderTracker-EnsureDir
    $path = _LadderTracker-EntryPath
    if (-not (Test-Path $path)) {
        "ts,market,template_id,regime,entry,atr,tps_count,sls_count,trade_id,notes" |
            Out-File -FilePath $path -Encoding utf8 -Force
    }

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $row = @(
        $ts,
        $Market,
        $TemplateId,
        $Regime,
        (_LadderTracker-InvString $Entry),
        (_LadderTracker-InvString $AtrValue),
        $TpsCount,
        $SlsCount,
        $TradeId,
        (_LadderTracker-CsvField $Notes)
    ) -join ","
    Add-Content -Path $path -Value $row -Encoding utf8
    return $row
}

# Add-LadderHitRecord ----------------------------------------------------------
# Quando TP ou SL bate (ou breakeven move), registra hit.
function Add-LadderHitRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $TemplateId,
        [Parameter(Mandatory)] [string] $HitType,    # "TP1","TP2","SL","BREAKEVEN","RUNNER_OUT"
        [Parameter(Mandatory)] [int]    $LevelIndex, # 1..N
        $HitPrice = 0,
        $QtyClosed = 0,
        $PnlR     = 0,
        $PnlUsd   = 0,
        [string]  $TradeId = "",
        [string]  $Regime  = "",
        [string]  $Notes   = ""
    )

    _LadderTracker-EnsureDir
    $path = _LadderTracker-HitPath
    if (-not (Test-Path $path)) {
        "ts,market,template_id,regime,hit_type,level_index,hit_price,qty_closed,pnl_r,pnl_usd,trade_id,notes" |
            Out-File -FilePath $path -Encoding utf8 -Force
    }

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $row = @(
        $ts,
        $Market,
        $TemplateId,
        $Regime,
        $HitType,
        $LevelIndex,
        (_LadderTracker-InvString $HitPrice),
        (_LadderTracker-InvString $QtyClosed),
        (_LadderTracker-InvString $PnlR),
        (_LadderTracker-InvString $PnlUsd),
        $TradeId,
        (_LadderTracker-CsvField $Notes)
    ) -join ","
    Add-Content -Path $path -Value $row -Encoding utf8
    return $row
}

# Get-LadderPerformance --------------------------------------------------------
# Agrega: por template_id Ã— regime. Win rate, avg R, runner survival, drawdown.
function Get-LadderPerformance {
    [CmdletBinding()]
    param(
        [string] $Month = $null,   # "YYYY-MM" filter (default: todos)
        [switch] $WriteJson
    )

    _LadderTracker-EnsureDir
    $entryPath = _LadderTracker-EntryPath
    $hitPath   = _LadderTracker-HitPath

    $empty = [PSCustomObject]@{
        generated_at  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        month         = $Month
        total_entries = 0
        total_hits    = 0
        by_template   = @()
    }

    if (-not (Test-Path $entryPath)) {
        if ($WriteJson) { _LadderTracker-WriteJson -Data $empty -Month $Month }
        return $empty
    }

    $entries = @(Import-Csv -Path $entryPath)
    $hits    = if (Test-Path $hitPath) { @(Import-Csv -Path $hitPath) } else { @() }

    if ($Month) {
        $entries = @($entries | Where-Object { $_.ts -and $_.ts.StartsWith($Month) })
        $hits    = @($hits    | Where-Object { $_.ts -and $_.ts.StartsWith($Month) })
    }

    if ($entries.Count -eq 0) {
        $empty.month = $Month
        if ($WriteJson) { _LadderTracker-WriteJson -Data $empty -Month $Month }
        return $empty
    }

    $groups = $entries | Group-Object -Property template_id, regime
    $rows = @()
    foreach ($g in $groups) {
        $tplId  = $g.Group[0].template_id
        $regime = $g.Group[0].regime
        $tplHits = $hits | Where-Object { $_.template_id -eq $tplId -and $_.regime -eq $regime }

        $tpHits = @($tplHits | Where-Object { $_.hit_type -like 'TP*' })
        $slHits = @($tplHits | Where-Object { $_.hit_type -eq 'SL' })
        $runners = @($tplHits | Where-Object { $_.hit_type -eq 'RUNNER_OUT' })

        $totalTrades = [int]$g.Count
        $wins = $tpHits.Count  # cada TP Ã© parcial win
        $winRate = if ($totalTrades -gt 0) {
            [math]::Round(($wins / [math]::Max(1, $totalTrades)), 4)
        } else { 0 }

        $pnlSum = 0.0
        foreach ($h in $tplHits) {
            try { $pnlSum += [double]$h.pnl_r } catch {}
        }
        $avgR = if ($totalTrades -gt 0) { [math]::Round($pnlSum / $totalTrades, 4) } else { 0 }

        $runnerSurvival = if ($totalTrades -gt 0) {
            [math]::Round($runners.Count / $totalTrades, 4)
        } else { 0 }

        # Drawdown simples: soma de pnl_r negativo (R-based)
        $dd = 0.0
        foreach ($h in $slHits) {
            try { $r = [double]$h.pnl_r; if ($r -lt 0) { $dd += $r } } catch {}
        }

        $rows += [PSCustomObject]@{
            template_id     = $tplId
            regime          = $regime
            trades          = $totalTrades
            tp_hits         = $tpHits.Count
            sl_hits         = $slHits.Count
            win_rate        = $winRate
            avg_r           = $avgR
            runner_survival = $runnerSurvival
            drawdown_r      = [math]::Round($dd, 4)
        }
    }

    $out = [PSCustomObject]@{
        generated_at  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        month         = $Month
        total_entries = $entries.Count
        total_hits    = $hits.Count
        by_template   = $rows
    }
    if ($WriteJson) { _LadderTracker-WriteJson -Data $out -Month $Month }
    return $out
}

function _LadderTracker-WriteJson {
    param($Data, $Month)
    _LadderTracker-EnsureDir
    $tag = if ($Month) { $Month } else { (Get-Date).ToString("yyyy-MM") }
    $out = Join-Path $global:JOURNAL_DIR "ladder_performance_$tag.json"
    $json = $Data | ConvertTo-Json -Depth 8
    $json | Out-File -FilePath $out -Encoding utf8 -Force
    return $out
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Get-LadderABReport â€” agrega A/B testing automatizado (template Ã— regime)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Get-LadderABReport {
    [CmdletBinding()]
    param(
        [Parameter()] [int] $WindowDays = 30
    )

    _LadderTracker-EnsureDir
    $entryPath = _LadderTracker-EntryPath
    $hitPath   = _LadderTracker-HitPath

    if (-not (Test-Path $entryPath)) {
        return @()
    }

    try {
        $entries = @(Import-Csv -Path $entryPath -ErrorAction Stop)
        $hits    = if (Test-Path $hitPath) { @(Import-Csv -Path $hitPath -ErrorAction Stop) } else { @() }

        if ($entries.Count -eq 0) {
            return @()
        }

        # Filtra por window de dias
        $now = Get-Date
        $windowStart = $now.AddDays(-$WindowDays)

        $entries = @($entries | Where-Object {
            if (-not $_.ts) { return $false }
            try {
                [DateTime]::Parse($_.ts) -ge $windowStart
            } catch {
                $false
            }
        })

        if ($entries.Count -eq 0) {
            return @()
        }

        $hits = @($hits | Where-Object {
            if (-not $_.ts) { return $false }
            try {
                [DateTime]::Parse($_.ts) -ge $windowStart
            } catch {
                $false
            }
        })

        # Agrupa por template_id (ignorando regime para ranking geral)
        $groups = $entries | Group-Object -Property template_id
        $reports = @()

        foreach ($g in $groups) {
            $tplId = $g.Name
            $tplEntries = @($g.Group)
            $tplHits = @($hits | Where-Object { $_.template_id -eq $tplId })

            if ($tplHits.Count -eq 0) {
                continue
            }

            # Calcula stats
            $tpHits = @($tplHits | Where-Object { $_.hit_type -like 'TP*' })
            $slHits = @($tplHits | Where-Object { $_.hit_type -eq 'SL' })
            $runners = @($tplHits | Where-Object { $_.hit_type -eq 'RUNNER_OUT' })

            $totalTrades = $tplEntries.Count
            $wins = $tpHits.Count
            $winRate = if ($totalTrades -gt 0) {
                [math]::Round(($wins / $totalTrades), 4)
            } else { 0 }

            $pnlSum = 0.0
            foreach ($h in $tplHits) {
                try { $pnlSum += [double]$h.pnl_r } catch {}
            }
            $avgR = if ($totalTrades -gt 0) {
                [math]::Round($pnlSum / $totalTrades, 4)
            } else { 0 }

            $runnerSurvival = if ($totalTrades -gt 0) {
                [math]::Round($runners.Count / $totalTrades, 4)
            } else { 0 }

            $reports += [PSCustomObject]@{
                template_id      = $tplId
                trades           = $totalTrades
                win_rate         = $winRate
                avg_r            = $avgR
                runner_survival_rate = $runnerSurvival
                tp_hits          = $tpHits.Count
                sl_hits          = $slHits.Count
            }
        }

        # Ordena por avg_r decrescente
        return @($reports | Sort-Object -Property avg_r -Descending)
    } catch {
        Write-Host "  [LadderAB] Erro ao gerar relatorio: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Export-LadderABReport â€” exporta relatorio em formato MD humanamente legivel
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function Export-LadderABReport {
    [CmdletBinding()]
    param(
        [Parameter()] [string] $OutputPath,
        [Parameter()] [int] $WindowDays = 30
    )

    _LadderTracker-EnsureDir

    # Default output path: journal/ladder_ab_report_YYYY-MM.md
    if (-not $OutputPath) {
        $tag = (Get-Date).ToString("yyyy-MM")
        $OutputPath = Join-Path $global:JOURNAL_DIR "ladder_ab_report_$tag.md"
    }

    $report = Get-LadderABReport -WindowDays $WindowDays

    $md = @"
# Ladder A/B Report

**Gerado em:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss Z")
**PerÃ­odo:** Ãšltimos $WindowDays dias

"@

    if ($report.Count -eq 0) {
        $md += @"
## Status

Sem dados registrados no perÃ­odo.
"@
    } else {
        $md += @"
## Ranking por Template

| Template ID | Trades | Win Rate | Avg R | Runner Survival | TP Hits | SL Hits |
|---|---|---|---|---|---|---|
"@
        foreach ($r in $report) {
            $md += "| $($r.template_id) | $($r.trades) | $($r.win_rate * 100)% | $($r.avg_r) | $($r.runner_survival_rate * 100)% | $($r.tp_hits) | $($r.sl_hits) |`n"
        }

        $md += @"

## Insights

- **Melhor template:** $($report[0].template_id) (avg R = $($report[0].avg_r))
- **Total templates testados:** $($report.Count)
- **Trades agregados:** $(($report | Measure-Object -Property trades -Sum).Sum)

"@
    }

    $md | Out-File -FilePath $OutputPath -Encoding utf8 -Force
    return $OutputPath
}
