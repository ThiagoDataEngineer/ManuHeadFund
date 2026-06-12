# lib_short_execution.ps1 -- SHORT Block 2: wiring scanner -> orchestrator
# 2026-05-28: Implementa pipeline de execucao SHORT.
#
# Funcoes:
#   Get-ShortCandidatesFromAlerts  -- le short_alerts.jsonl, filtra por idade
#   Merge-ShortCandidatesIntoScan  -- injeta candidatos SHORT no scan_master pipeline
#
# Fluxo:
#   short_scanner.ps1 detecta sinal -> escreve short_alerts.jsonl
#   scan_master.ps1 chama Get-ShortCandidatesFromAlerts a cada ciclo
#   Merge-ShortCandidatesIntoScan injeta no topCandidates
#   Invoke-OrchestratorV6 processa normalmente (direction=SHORT ja suportado)
#
# PS 5.1. UTF-8 BOM.


function Get-ShortCandidatesFromAlerts {
    <#
    .SYNOPSIS
    Le short_alerts.jsonl e retorna candidatos SHORT recentes para o orchestrator.

    .PARAMETER AlertsPath
    Caminho para o arquivo short_alerts.jsonl.

    .PARAMETER MaxAgeHours
    Filtra alertas mais antigos que N horas. Default 24.

    .PARAMETER ExcludeMarkets
    Array de PSCustomObject com campo .market -- mercados ja presentes como LONG.
    Evita que o mesmo par entre como LONG e SHORT no mesmo ciclo.

    .OUTPUTS
    Array de PSCustomObject com campos: market, direction, compScore, vol_ratio,
    current_close, source, isWhitelistForced, tierLevel
    #>
    [CmdletBinding()]
    param(
        [string]  $AlertsPath    = "",
        [int]     $MaxAgeHours   = 24,
        [object[]]$ExcludeMarkets = @()
    )

    if (-not $AlertsPath) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else {
            Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
        }
        $AlertsPath = Join-Path $journalDir "short_alerts.jsonl"
    }

    if (-not (Test-Path $AlertsPath)) { return @() }

    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$MaxAgeHours)

    # Monta set de mercados a excluir
    $excludeSet = @{}
    foreach ($e in $ExcludeMarkets) {
        if ($e -and $e.market) { $excludeSet[$e.market] = $true }
    }

    $candidates = @()
    try {
        $lines = Get-Content $AlertsPath -Encoding UTF8 -ErrorAction Stop
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $alert = $line | ConvertFrom-Json -ErrorAction Stop
                if (-not $alert.market -or -not $alert.ts_utc) { continue }

                # Filtro de idade
                $ts = [datetime]::Parse($alert.ts_utc).ToUniversalTime()
                if ($ts -lt $cutoff) { continue }

                # Filtro de exclusao (mercado ja como LONG)
                if ($excludeSet.ContainsKey($alert.market)) { continue }

                # Monta candidato no formato esperado pelo scan_master
                $volRatio = if ($alert.vol_ratio) { [double]$alert.vol_ratio } else { 1.0 }
                $close    = if ($alert.current_close) { [double]$alert.current_close } else { 0 }

                # compScore para SHORT: vol_ratio * 0.6 (peso maior em vol para shorts)
                $compScore = [math]::Round($volRatio * 0.6, 4)

                $candidates += [PSCustomObject]@{
                    market           = [string]$alert.market
                    direction        = "SHORT"
                    compScore        = $compScore
                    compScoreBase    = $compScore
                    vol_ratio        = $volRatio
                    current_close    = $close
                    rsi              = if ($alert.rsi) { [double]$alert.rsi } else { 0 }
                    pattern          = if ($alert.pattern) { [string]$alert.pattern } else { "SHORT_climax" }
                    wss              = if ($alert.wss) { [double]$alert.wss } else { 0 }
                    wss_tier         = if ($alert.wss_tier) { [string]$alert.wss_tier } else { "U" }
                    source           = "short_alerts"
                    isWhitelistForced = $true   # SHORT candidates sao pre-validados pelo scanner
                    tierLevel        = 2         # Tier B equivalente (SHORT_TIER_B_PAPER)
                    passes           = 4         # bypass pre-screen (scanner ja validou)
                    adx              = 0
                    rsi_val          = if ($alert.rsi) { [double]$alert.rsi } else { 0 }
                    vol              = $volRatio
                    momentum         = 0
                    alert_ts         = $alert.ts_utc
                }
            } catch { continue }
        }
    } catch { return @() }

    # Dedup: se mesmo mercado aparece multiplas vezes, pega o mais recente
    $deduped = @{}
    foreach ($c in $candidates) {
        if (-not $deduped.ContainsKey($c.market)) {
            $deduped[$c.market] = $c
        } else {
            # Compara timestamps, mantém o mais recente
            $existing = $deduped[$c.market]
            if ($c.alert_ts -gt $existing.alert_ts) {
                $deduped[$c.market] = $c
            }
        }
    }

    return @($deduped.Values)
}


function Merge-ShortCandidatesIntoScan {
    <#
    .SYNOPSIS
    Injeta candidatos SHORT no array de candidatos do scan_master.

    .DESCRIPTION
    Recebe os candidatos LONG do scanner normal e os candidatos SHORT do
    short_alerts.jsonl. Retorna array combinado sem duplicatas de mercado.

    Regra de dedup: se um mercado ja esta como LONG, nao adiciona como SHORT
    no mesmo ciclo (evita posicoes conflitantes).

    .PARAMETER LongCandidates
    Array de candidatos LONG do scanner normal.

    .PARAMETER ShortAlerts
    Array de candidatos SHORT de Get-ShortCandidatesFromAlerts.

    .OUTPUTS
    Array combinado de candidatos (LONG + SHORT sem duplicatas).
    #>
    [CmdletBinding()]
    param(
        [object[]]$LongCandidates = @(),
        [object[]]$ShortAlerts    = @()
    )

    if (-not $ShortAlerts -or @($ShortAlerts).Count -eq 0) {
        return @($LongCandidates)
    }

    # Monta set de mercados ja presentes como LONG
    $longSet = @{}
    foreach ($c in $LongCandidates) {
        if ($c -and $c.market) { $longSet[$c.market] = $true }
    }

    $result = @($LongCandidates)

    foreach ($short in $ShortAlerts) {
        if (-not $short -or -not $short.market) { continue }
        # Nao adiciona se mercado ja esta como LONG
        if ($longSet.ContainsKey($short.market)) { continue }
        $result += $short
    }

    return @($result)
}
