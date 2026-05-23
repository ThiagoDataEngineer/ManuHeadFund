# lib_hit_rate.ps1 -- Hit rate analysis: scanner vs universe movers
#
# Contrato:
#   Compare-ScannerVsUniverse -ScannerTopN -UniverseMovers -Direction
#     => PSCustomObject:
#        total_movers, caught_by_scanner, missed, hit_rate_pct, direction
#
#   Get-HitRateMetrics -LongComparison -ShortComparison
#     => PSCustomObject (long_hit_rate_pct, short_hit_rate_pct, ...)
#
# Sem dependencias externas. Pure functions. UTF-8 BOM.

function Compare-ScannerVsUniverse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $ScannerTopN,
        [Parameter(Mandatory=$false)] [AllowEmptyCollection()] [object[]] $UniverseMovers,
        [Parameter()] [string] $Direction = "LONG"
    )

    $total = if ($null -eq $UniverseMovers -or $UniverseMovers.Count -eq 0) { 0 } else { $UniverseMovers.Count }

    if ($total -eq 0) {
        return [PSCustomObject]@{
            total_movers      = 0
            caught_by_scanner = 0
            missed            = @()
            hit_rate_pct      = 0
            direction         = $Direction
        }
    }

    # Converter para lowercase para case-insensitive matching
    $scanner_normalized = @()
    foreach ($sym in $ScannerTopN) {
        if ($null -ne $sym) {
            $scanner_normalized += ([string]$sym).ToLower()
        }
    }

    $movers_normalized = @()
    foreach ($sym in $UniverseMovers) {
        if ($null -ne $sym) {
            $movers_normalized += ([string]$sym).ToLower()
        }
    }

    $caught = 0
    $missed = @()

    foreach ($mover in $movers_normalized) {
        if ($scanner_normalized -contains $mover) {
            $caught++
        } else {
            $missed += $mover
        }
    }

    $hit_rate = if ($total -gt 0) { ([double]$caught / $total) * 100 } else { 0 }

    return [PSCustomObject]@{
        total_movers      = $total
        caught_by_scanner = $caught
        missed            = $missed
        hit_rate_pct      = $hit_rate
        direction         = $Direction
    }
}

function Get-HitRateMetrics {
    [CmdletBinding()]
    param(
        [Parameter()] [object] $LongComparison,
        [Parameter()] [object] $ShortComparison
    )

    $long_hr = if ($null -ne $LongComparison) { $LongComparison.hit_rate_pct } else { 0 }
    $short_hr = if ($null -ne $ShortComparison) { $ShortComparison.hit_rate_pct } else { 0 }

    return [PSCustomObject]@{
        long_hit_rate_pct  = $long_hr
        short_hit_rate_pct = $short_hr
        long_comparison    = $LongComparison
        short_comparison   = $ShortComparison
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-ScannerHealth — valida se scanner hit rate esta saudavel (acima de MinAvg)
# ─────────────────────────────────────────────────────────────────────────────
function Test-ScannerHealth {
    [CmdletBinding()]
    param(
        [Parameter()] [AllowEmptyCollection()] [double[]] $RecentHitRates,
        [Parameter()] [double] $MinAvg = 0.30
    )

    if ($null -eq $RecentHitRates -or $RecentHitRates.Count -eq 0) {
        return $false
    }

    $avg = ($RecentHitRates | Measure-Object -Average).Average
    return $avg -ge $MinAvg
}

# ─────────────────────────────────────────────────────────────────────────────
# Add-HitRateRecord — registra hit rate no journal
# ─────────────────────────────────────────────────────────────────────────────
function Add-HitRateRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [double] $Rate,
        [Parameter(Mandatory)] [int] $Caught,
        [Parameter(Mandatory)] [int] $Total
    )

    if (-not $global:JOURNAL_DIR) {
        $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
    }

    if (-not (Test-Path $global:JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
    }

    $path = Join-Path $global:JOURNAL_DIR "hit_rate_history.csv"

    if (-not (Test-Path $path)) {
        "timestamp,direction,rate,caught,total" |
            Out-File -FilePath $path -Encoding utf8 -Force
    }

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $rateStr = $Rate.ToString("F4", $inv)

    $row = @(
        $ts,
        $Direction,
        $rateStr,
        $Caught,
        $Total
    ) -join ","

    Add-Content -Path $path -Value $row -Encoding utf8
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-HitRateHealth — valida saude do hit rate (GREEN/YELLOW/RED)
# Retorna @{health: "GREEN"|"YELLOW"|"RED", reason, consecutive_low}
# ─────────────────────────────────────────────────────────────────────────────
function Test-HitRateHealth {
    [CmdletBinding()]
    param(
        [Parameter()] [double] $MinHitRatePct = 30,
        [Parameter()] [int] $ConsecutiveCyclesThreshold = 5,
        [Parameter()] [string] $HistoryFile
    )

    if (-not $global:JOURNAL_DIR) {
        $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
    }

    if ([string]::IsNullOrEmpty($HistoryFile)) {
        $HistoryFile = Join-Path $global:JOURNAL_DIR "hit_rate_history.csv"
    }

    if (-not (Test-Path $HistoryFile)) {
        return [PSCustomObject]@{
            health             = "GREEN"
            reason             = "no_data"
            consecutive_low    = 0
            sample_size        = 0
        }
    }

    try {
        # Detecta header invalido (sem coluna 'rate') -> arquivo corrompido
        $firstLine = (Get-Content $HistoryFile -TotalCount 1 -ErrorAction Stop)
        if ([string]::IsNullOrWhiteSpace($firstLine) -or $firstLine -notmatch ",") {
            return [PSCustomObject]@{
                health             = "GREEN"
                reason             = "error_reading_file"
                consecutive_low    = 0
                sample_size        = 0
            }
        }

        $rows = Import-Csv $HistoryFile -ErrorAction Stop
        if ($null -eq $rows -or $rows.Count -eq 0) {
            return [PSCustomObject]@{
                health             = "GREEN"
                reason             = "no_data"
                consecutive_low    = 0
                sample_size        = 0
            }
        }

        # Garante array mesmo com 1 row
        if ($rows -isnot [array]) {
            $rows = @($rows)
        }

        # Header sem coluna 'rate' tambem indica corrompido
        if (-not ($rows[0].PSObject.Properties.Name -contains 'rate')) {
            return [PSCustomObject]@{
                health             = "GREEN"
                reason             = "error_reading_file"
                consecutive_low    = 0
                sample_size        = 0
            }
        }

        # Captura ultimos 100 ciclos (rolling window)
        $recent = if ($rows.Count -gt 100) {
            $rows[-100..-1]
        } else {
            $rows
        }

        # Converte rates para double
        $rates = @()
        foreach ($r in $recent) {
            $rate = [double]$r.rate
            $rates += $rate
        }

        $avgRate = ($rates | Measure-Object -Average).Average
        $avgRatePct = $avgRate * 100

        # Conta ciclos consecutivos com hit rate baixo (tail)
        $consecutiveLow = 0
        for ($i = $recent.Count - 1; $i -ge 0; $i--) {
            $rate = [double]$recent[$i].rate
            if ($rate * 100 -lt $MinHitRatePct) {
                $consecutiveLow++
            } else {
                break
            }
        }

        # Logica de saude
        $health = "GREEN"
        $reason = "healthy"

        if ($consecutiveLow -ge $ConsecutiveCyclesThreshold) {
            $health = "RED"
            $reason = "consecutive_low_cycles"
        } elseif ($avgRatePct -lt $MinHitRatePct) {
            $health = "YELLOW"
            $reason = "below_min_threshold"
        } elseif ($consecutiveLow -gt 0 -and $consecutiveLow -lt $ConsecutiveCyclesThreshold) {
            $health = "YELLOW"
            $reason = "trend_downward"
        }

        return [PSCustomObject]@{
            health             = $health
            reason             = $reason
            consecutive_low    = $consecutiveLow
            sample_size        = $recent.Count
            avg_hit_rate_pct   = [math]::Round($avgRatePct, 2)
            min_threshold_pct  = $MinHitRatePct
        }
    } catch {
        return [PSCustomObject]@{
            health             = "GREEN"
            reason             = "error_reading_file"
            consecutive_low    = 0
            sample_size        = 0
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Add-HitRateLog — registra hit rate no historico (max 100 rolling)
# Retorna PSCustomObject com dados registrados
# ─────────────────────────────────────────────────────────────────────────────
function Add-HitRateLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double] $HitRateLong,
        [Parameter(Mandatory)] [double] $HitRateShort,
        [Parameter()] [int] $UniverseSize = 0,
        [Parameter()] [string] $HistoryFile
    )

    if (-not $global:JOURNAL_DIR) {
        $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
    }

    if (-not (Test-Path $global:JOURNAL_DIR)) {
        New-Item -ItemType Directory -Path $global:JOURNAL_DIR -Force | Out-Null
    }

    if ([string]::IsNullOrEmpty($HistoryFile)) {
        $HistoryFile = Join-Path $global:JOURNAL_DIR "hit_rate_history.csv"
    }

    # Calcula hit rate medio
    $avgHitRate = ($HitRateLong + $HitRateShort) / 2.0

    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $rateStr = $avgHitRate.ToString("F4", $inv)

    # Cria header se arquivo nao existe
    if (-not (Test-Path $HistoryFile)) {
        "timestamp,direction,rate,caught,total,universe_size" |
            Out-File -FilePath $HistoryFile -Encoding utf8 -Force
    }

    # Registra com direction "LONG" e "SHORT" como duas linhas
    $row1 = @($ts, "LONG", ([math]::Round($HitRateLong, 4)).ToString("F4", $inv), 0, 0, $UniverseSize) -join ","
    $row2 = @($ts, "SHORT", ([math]::Round($HitRateShort, 4)).ToString("F4", $inv), 0, 0, $UniverseSize) -join ","

    Add-Content -Path $HistoryFile -Value $row1 -Encoding utf8
    Add-Content -Path $HistoryFile -Value $row2 -Encoding utf8

    # Trunca arquivo a ultimas 100 records para manter tamanho
    try {
        $all = Get-Content $HistoryFile -Raw
        $lines = $all -split "(`r`n|`r|`n)" | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^[`r`n]+$" }
        if ($lines.Count -gt 101) {  # header + 100 records
            $kept = @($lines[0]) + $lines[-100..-1]
            # Usa Set-Content para gerar line endings nativos (CRLF no Windows) sem trailing newline extra
            Set-Content -Path $HistoryFile -Value $kept -Encoding utf8 -Force
        }
    } catch {
        # Nao falha se nao conseguir truncar
    }

    return [PSCustomObject]@{
        timestamp      = $ts
        hit_rate_long  = $HitRateLong
        hit_rate_short = $HitRateShort
        avg_hit_rate   = $avgHitRate
        universe_size  = $UniverseSize
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-HitRateAlarmStatus — retorna status do scanner health com ultimos N ciclos
# ─────────────────────────────────────────────────────────────────────────────
function Get-HitRateAlarmStatus {
    [CmdletBinding()]
    param(
        [Parameter()] [int] $MinCycles = 3
    )

    if (-not $global:JOURNAL_DIR) {
        $global:JOURNAL_DIR = Join-Path $PSScriptRoot "..\journal"
    }

    $path = Join-Path $global:JOURNAL_DIR "hit_rate_history.csv"

    if (-not (Test-Path $path)) {
        return @()
    }

    try {
        $rows = Import-Csv $path -ErrorAction Stop
        if ($null -eq $rows) {
            return @()
        }

        # Garante que eh array mesmo com 1 row
        if ($rows -isnot [array]) {
            $rows = @($rows)
        }

        if ($rows.Count -lt $MinCycles) {
            return [PSCustomObject]@{
                status = "insufficient_data"
                cycles_count = $rows.Count
                min_required = $MinCycles
            }
        }

        # Agrupa por direction e calcula medias
        $byDirection = @{}
        foreach ($r in $rows) {
            $dir = $r.direction
            if (-not $byDirection.ContainsKey($dir)) {
                $byDirection[$dir] = @()
            }
            $byDirection[$dir] += @{
                rate = [double]$r.rate
                caught = [int]$r.caught
                total = [int]$r.total
            }
        }

        $statuses = @()
        foreach ($entry in $byDirection.GetEnumerator()) {
            $dir = $entry.Key
            $rates = $entry.Value | ForEach-Object { $_.rate }
            $avgRate = ($rates | Measure-Object -Average).Average
            $healthy = $avgRate -ge 0.30

            $statuses += [PSCustomObject]@{
                direction = $dir
                avg_hit_rate = [math]::Round($avgRate, 4)
                cycles = $rates.Count
                healthy = $healthy
                recommendation = if ($healthy) { "OK" } else { "REVISAR: hit rate baixo" }
            }
        }

        return $statuses
    } catch {
        Write-Host "  [HitRateGate] Erro ao ler hit_rate_history: $_" -ForegroundColor DarkYellow
        return @()
    }
}
