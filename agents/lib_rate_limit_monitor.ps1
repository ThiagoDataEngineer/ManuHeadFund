# lib_rate_limit_monitor.ps1 -- Monitoramento de rate-limit events (4213/429)
# Observabilidade: loga eventos em JSONL, contadores, queries, health-check, report.
# PS 5.1. UTF-8 BOM.

# ============================================================================
# Initialize-RateLimitMonitor - Setup do monitor (log path + contadores)
# ============================================================================
function Initialize-RateLimitMonitor {
    [CmdletBinding()]
    param(
        [string]$LogPath = ""
    )
    if (-not $LogPath) {
        $journalDir = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
        if (-not (Test-Path $journalDir)) { New-Item -ItemType Directory -Path $journalDir -Force | Out-Null }
        $LogPath = Join-Path $journalDir "rate_limit_events.jsonl"
    }
    $dir = Split-Path $LogPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $LogPath)) { New-Item -ItemType File -Path $LogPath -Force | Out-Null }

    $global:RATE_LIMIT_MONITOR = [PSCustomObject]@{
        log_path      = $LogPath
        total_events  = 0
        events_today  = 0
        started_at    = (Get-Date).ToString("o")
    }
    return $global:RATE_LIMIT_MONITOR
}

# ============================================================================
# Log-RateLimitEvent - Registra um evento de rate-limit no log JSONL
# ============================================================================
function Log-RateLimitEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$ErrorCode,
        [Parameter(Mandatory)] [string]$Category,
        [string]$Market = ""
    )
    if (-not $global:RATE_LIMIT_MONITOR) { Initialize-RateLimitMonitor | Out-Null }
    $evt = [ordered]@{
        timestamp  = (Get-Date).ToString("o")
        error_code = $ErrorCode
        category   = $Category
        market     = $Market
    }
    $line = $evt | ConvertTo-Json -Compress
    Add-Content -Path $global:RATE_LIMIT_MONITOR.log_path -Value $line -Encoding UTF8

    $global:RATE_LIMIT_MONITOR.total_events += 1
    $global:RATE_LIMIT_MONITOR.events_today += 1
    return $evt
}

# ============================================================================
# Get-RateLimitEvents - Le eventos do log com filtros opcionais
# ============================================================================
function Get-RateLimitEvents {
    [CmdletBinding()]
    param(
        [int]   $Hours    = 0,       # 0 = todos
        [string]$Category = "",
        [string]$Market   = ""
    )
    if (-not $global:RATE_LIMIT_MONITOR -or -not (Test-Path $global:RATE_LIMIT_MONITOR.log_path)) { return @() }
    $cutoff = if ($Hours -gt 0) { (Get-Date).AddHours(-$Hours) } else { [datetime]::MinValue }

    $events = @()
    foreach ($line in (Get-Content $global:RATE_LIMIT_MONITOR.log_path -EA SilentlyContinue)) {
        if (-not $line.Trim()) { continue }
        try { $e = $line | ConvertFrom-Json } catch { continue }
        if (-not $e) { continue }
        $ts = try { [datetime]::Parse($e.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { [datetime]::MinValue }
        if ($ts -lt $cutoff) { continue }
        if ($Category -and $e.category -ne $Category) { continue }
        if ($Market   -and $e.market   -ne $Market)   { continue }
        $events += $e
    }
    return $events
}

# ============================================================================
# Get-RateLimitSummary - Resumo agregado (totais, por categoria, por market, taxa)
# ============================================================================
function Get-RateLimitSummary {
    [CmdletBinding()]
    param()
    $all   = @(Get-RateLimitEvents)
    $lastH = @(Get-RateLimitEvents -Hours 1)
    $last24= @(Get-RateLimitEvents -Hours 24)

    $byCategory = @{}
    $byMarket   = @{}
    foreach ($e in $all) {
        if ($e.category) {
            if (-not $byCategory.ContainsKey($e.category)) { $byCategory[$e.category] = 0 }
            $byCategory[$e.category] += 1
        }
        if ($e.market) {
            if (-not $byMarket.ContainsKey($e.market)) { $byMarket[$e.market] = 0 }
            $byMarket[$e.market] += 1
        }
    }

    # Taxa por hora: eventos da ultima hora (ou total/janela se < 1h de dados)
    $eventsPerHour = $lastH.Count

    return [PSCustomObject]@{
        total_events     = $all.Count
        events_last_hour = $lastH.Count
        events_last_24h  = $last24.Count
        events_per_hour  = $eventsPerHour
        by_category      = $byCategory
        by_market        = $byMarket
    }
}

# ============================================================================
# Test-RateLimitHealthy - Health-check baseado em taxa de eventos
# ============================================================================
function Test-RateLimitHealthy {
    [CmdletBinding()]
    param(
        [int]$ThresholdPerHour = 10
    )
    $summary = Get-RateLimitSummary
    $rate = $summary.events_last_hour
    $healthy = $rate -le $ThresholdPerHour

    $recommendations = @()
    $reason = "ok"
    if (-not $healthy) {
        $reason = "rate limit threshold exceeded ($rate eventos/hora > $ThresholdPerHour)"
        $recommendations += "Reduzir frequencia de ordens (aumentar intervalo entre trades)"
        $recommendations += "Verificar se ha retry loop sem backoff exponencial"
        $recommendations += "Considerar segunda API key para dobrar o rate limit"
        # Categoria mais afetada
        if ($summary.by_category.Count -gt 0) {
            $topCat = ($summary.by_category.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
            $recommendations += "Categoria mais afetada: $($topCat.Key) ($($topCat.Value) eventos)"
        }
    }

    return [PSCustomObject]@{
        healthy          = $healthy
        reason           = $reason
        events_last_hour = $rate
        threshold        = $ThresholdPerHour
        recommendations  = $recommendations
    }
}

# ============================================================================
# Clear-OldRateLimitEvents - Remove eventos mais antigos que N dias
# ============================================================================
function Clear-OldRateLimitEvents {
    [CmdletBinding()]
    param(
        [int]$DaysToKeep = 7
    )
    try {
        if (-not $global:RATE_LIMIT_MONITOR -or -not (Test-Path $global:RATE_LIMIT_MONITOR.log_path)) {
            return [PSCustomObject]@{ success = $true; removed = 0; kept = 0 }
        }
        $cutoff = (Get-Date).AddDays(-$DaysToKeep)
        $kept = @()
        $removed = 0
        foreach ($line in (Get-Content $global:RATE_LIMIT_MONITOR.log_path -EA SilentlyContinue)) {
            if (-not $line.Trim()) { continue }
            try { $e = $line | ConvertFrom-Json } catch { continue }
            $ts = try { [datetime]::Parse($e.timestamp, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { [datetime]::MinValue }
            if ($ts -ge $cutoff) { $kept += $line } else { $removed += 1 }
        }
        Set-Content -Path $global:RATE_LIMIT_MONITOR.log_path -Value $kept -Encoding UTF8
        return [PSCustomObject]@{ success = $true; removed = $removed; kept = $kept.Count }
    } catch {
        return [PSCustomObject]@{ success = $false; error = $_.Exception.Message }
    }
}

# ============================================================================
# Export-RateLimitReport - Gera relatorio em texto ou JSON
# ============================================================================
function Export-RateLimitReport {
    [CmdletBinding()]
    param(
        [ValidateSet("text","json")] [string]$Format = "text"
    )
    $summary = Get-RateLimitSummary

    if ($Format -eq "json") {
        return ($summary | ConvertTo-Json -Depth 4)
    }

    $lines = @()
    $lines += "=== Rate Limit Events Report ==="
    $lines += "Total: $($summary.total_events)"
    $lines += "Ultima hora: $($summary.events_last_hour)"
    $lines += "Ultimas 24h: $($summary.events_last_24h)"
    $lines += "Taxa/hora: $($summary.events_per_hour)"
    if ($summary.by_category.Count -gt 0) {
        $lines += "`nPor categoria:"
        foreach ($k in ($summary.by_category.Keys | Sort-Object)) {
            $lines += "  $k : $($summary.by_category[$k])"
        }
    }
    if ($summary.by_market.Count -gt 0) {
        $lines += "`nPor market:"
        foreach ($k in ($summary.by_market.Keys | Sort-Object)) {
            $lines += "  $k : $($summary.by_market[$k])"
        }
    }
    return ($lines -join "`n")
}
