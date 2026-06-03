# lib_cluster_filter.ps1 -- Cluster filter pra signal alerts (risk control).
#
# Filosofia: vol_climax_refined dispara em K markets simultaneos em capitulacoes
# correlacionadas (ex: Jan 31 2026 = 7 markets mesmo dia). Sem filter, ativar
# trade = K-leg exposure macro (1 macro-bet errada perde K vezes).
#
# Cluster filter NAO restaura edge no holdout (backtest 2026-05-22 confirmou
# 0/3 com filter vs 1/12 sem). Existe como RISK CONTROL: simula comportamento
# real se ativassemos trade, capando exposure portfolio.
#
# Default policy: max 1 signal/dia, max 3 signal/7d (ROLLING window).
# Source de truth: arquivo JSONL append-only (1 line por alert).
#
# PS 5.1. UTF-8 BOM.


function Test-ClusterCapExceeded {
    <#
    .SYNOPSIS
    Verifica se proximo alert excede caps diario/semanal baseado em historico JSONL.

    .DESCRIPTION
    Le JSONL (uma entry por linha), filtra entries com ts_utc >= cutoff,
    conta e compara com MaxPerDay / MaxPerWeek. Retorna PSCustomObject:
      .day_count    int
      .week_count   int
      .day_exceeded bool
      .week_exceeded bool
      .exceeded     bool   (qualquer um)
      .reason       string (motivo se exceeded)

    Fail-open: se arquivo nao existe ou parse falha, retorna nao-exceeded.
    Isso eh proposital: cluster filter NAO deve bloquear operacao por bug
    de filesystem; pior caso loga K alerts em vez de 1, ja eh observado.

    .PARAMETER AlertsPath
    Caminho JSONL append-only com entries {ts_utc, market, ...}.

    .PARAMETER NowUtc
    Timestamp de referencia (default = agora UTC). Injetavel pra teste.

    .PARAMETER MaxPerDay
    Cap rolling 24h. Default 1.

    .PARAMETER MaxPerWeek
    Cap rolling 7d. Default 3.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AlertsPath,
        [datetime] $NowUtc = (Get-Date).ToUniversalTime(),
        [int] $MaxPerDay = 1,
        [int] $MaxPerWeek = 3
    )

    $result = [PSCustomObject]@{
        day_count     = 0
        week_count    = 0
        day_exceeded  = $false
        week_exceeded = $false
        exceeded      = $false
        reason        = ""
    }

    if (-not (Test-Path $AlertsPath)) { return $result }

    $cutoffDay  = $NowUtc.AddHours(-24)
    $cutoffWeek = $NowUtc.AddDays(-7)

    try {
        $lines = Get-Content -Path $AlertsPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        return $result  # fail-open
    }

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $obj = $null
        try { $obj = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if (-not $obj -or -not $obj.ts_utc) { continue }

        # Parse robusto (suporta sufixo Z + offset). Forca UTC.
        $ts = $null
        try {
            $dto = [System.DateTimeOffset]::Parse($obj.ts_utc, [System.Globalization.CultureInfo]::InvariantCulture)
            $ts = $dto.UtcDateTime
        } catch { continue }

        if ($ts -gt $cutoffWeek) { $result.week_count++ }
        if ($ts -gt $cutoffDay)  { $result.day_count++  }
    }

    if ($result.day_count -ge $MaxPerDay) {
        $result.day_exceeded = $true
        $result.exceeded = $true
        $result.reason = "day_cap_$($result.day_count)/$MaxPerDay"
    }
    if ($result.week_count -ge $MaxPerWeek) {
        $result.week_exceeded = $true
        $result.exceeded = $true
        if ($result.reason) { $result.reason = $result.reason + ";" }
        $result.reason = $result.reason + "week_cap_$($result.week_count)/$MaxPerWeek"
    }

    return $result
}